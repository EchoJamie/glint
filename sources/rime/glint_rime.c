//
//  glint_rime.c
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

#include "glint_rime.h"

// 顺序要紧：rime_api_stdbool.h 通过 RIME_FLAVORED 和 Bool 的 #ifndef 守卫
// 影响后面 rime_api.h 的声明，反过来的话拿不到 *_stdbool 那套符号。
#include <rime_api_stdbool.h>
#include <rime_api.h>
#include <rime_levers_api.h>

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

/// librime 的函数指针表。rime_get_api_stdbool() 返回进程内单例，取一次即可。
static const RIME_FLAVORED(RimeApi) *glint_api(void) {
  static const RIME_FLAVORED(RimeApi) *api = NULL;
  if (api == NULL) {
    api = rime_get_api_stdbool();
  }
  return api;
}

static int deployment_result = -1;
static void deployment_notification(void *context, RimeSessionId session,
                                     const char *type, const char *value) {
  (void)context; (void)session;
  if (strcmp(type, "deploy") == 0) {
    if (strcmp(value, "success") == 0) deployment_result = 0;
    if (strcmp(value, "failure") == 0) deployment_result = -1;
  }
}

// ---------------------------------------------------------------- 生命周期

int glint_rime_start(const char *app_name,
                     const char *user_data_dir,
                     const char *shared_data_dir,
                     const char *log_dir) {
  if (user_data_dir == NULL || shared_data_dir == NULL) {
    return -1;
  }

  // **必须零初始化**：`RIME_STRUCT_INIT` 只设 `data_size`，不清其余字段。
  // 只写它而变量又未初始化时，没被显式赋值的成员（modules / min_log_level /
  // prebuilt_data_dir / staging_dir）会是栈上的垃圾值；librime 按 data_size
  // 读取它们，`modules` 一旦是非空垃圾指针，就在 SetupDeployer 里解引用崩溃
  // （实测：SIGSEGV，崩在 rime::SetupDeployer，访问地址 0x14）。
  // `RIME_STRUCT` 宏自带 `= {0}`，正是为这种情况准备的。
  RimeTraits traits = {0};
  RIME_STRUCT_INIT(RimeTraits, traits);
  traits.shared_data_dir = shared_data_dir;
  traits.user_data_dir = user_data_dir;
  traits.log_dir = log_dir;
  traits.distribution_name = "流光";
  traits.distribution_code_name = "Glint";
  traits.distribution_version = "0.1.0";
  // "rime." 前缀便于 librime 清理旧日志。
  traits.app_name = app_name;

  size_t installation_capacity = strlen(user_data_dir) + sizeof("/installation.yaml");
  char *installation_path = malloc(installation_capacity);
  if (!installation_path) return -1;
  snprintf(installation_path, installation_capacity, "%s/installation.yaml", user_data_dir);
  int first_installation = access(installation_path, F_OK) != 0;
  free(installation_path);

  glint_api()->setup(&traits);
  // 传 NULL 表示沿用 setup 里给的 traits。
  glint_api()->initialize(NULL);
  glint_api()->set_notification_handler(deployment_notification, NULL);
  glint_api()->deployer_initialize(NULL);
  // Rime 首次创建 installation.yaml 的分支不设置 sync_dir；创建后读回一次。
  if (!glint_api()->run_task("installation_update") ||
      (first_installation && !glint_api()->run_task("installation_update"))) {
    glint_api()->finalize();
    return -1;
  }
  return 0;
}

void glint_rime_finalize(void) {
  glint_api()->join_maintenance_thread();
  glint_api()->finalize();
}

int glint_rime_deploy(void) {
  deployment_result = -1;
  if (!glint_api()->start_maintenance(True)) {
    return -1;
  }
  glint_api()->join_maintenance_thread();
  return deployment_result;
}

const char *glint_rime_version(void) { return glint_api()->get_version(); }

// ------------------------------------------------------------------ 会话

int64_t glint_rime_create_session(void) {
  return (int64_t)glint_api()->create_session();
}

void glint_rime_set_option(int64_t session, const char *name, int enabled) {
  if (glint_rime_session_alive(session) && name) {
    glint_api()->set_option((RimeSessionId)session, name, enabled != 0);
  }
}

void glint_rime_destroy_session(int64_t session) {
  if (session != 0) {
    glint_api()->destroy_session((RimeSessionId)session);
  }
}

int glint_rime_session_alive(int64_t session) {
  if (session == 0) {
    return 0;
  }
  return glint_api()->find_session((RimeSessionId)session) ? 1 : 0;
}

// ------------------------------------------------------------------ 输入

int glint_rime_process_key(int64_t session, int keycode, int mask) {
  if (!glint_rime_session_alive(session)) {
    return 0;
  }
  return glint_api()->process_key((RimeSessionId)session, keycode, mask) ? 1 : 0;
}

const char *glint_rime_get_input(int64_t session) {
  if (!glint_rime_session_alive(session)) {
    return NULL;
  }
  return glint_api()->get_input((RimeSessionId)session);
}

/// 把 src 拷进调用方的缓冲，返回写入字节数（不含结尾的 '\0'）。
/// 返回 -1 表示缓冲不够——调用方据此知道要换更大的缓冲，而不是拿到半截文本。
static int copy_out(const char *src, char *out, size_t out_len) {
  if (out == NULL || out_len == 0) {
    return -1;
  }
  if (src == NULL) {
    out[0] = '\0';
    return 0;
  }
  size_t len = strlen(src);
  if (len >= out_len) {
    out[0] = '\0';
    return -1;
  }
  memcpy(out, src, len + 1);
  return (int)len;
}

size_t glint_rime_caret_pos(int64_t session) {
  return glint_rime_session_alive(session) ? glint_api()->get_caret_pos((RimeSessionId)session) : 0;
}

int glint_rime_get_preedit(int64_t session, char *out, size_t out_len, int *cursor) {
  if (!glint_rime_session_alive(session)) {
    return -1;
  }
  // 零初始化，理由同 glint_rime_start：`RIME_STRUCT_INIT` 只设 data_size，
  // 未赋值的成员会是栈垃圾，而 librime 的 free_context 会按 data_size 处理它们。
  RIME_FLAVORED(RimeContext) ctx = {0};
  RIME_STRUCT_INIT(RIME_FLAVORED(RimeContext), ctx);
  if (!glint_api()->get_context((RimeSessionId)session, &ctx)) {
    return -1;
  }
  int written = copy_out(ctx.composition.preedit, out, out_len);
  if (cursor != NULL) *cursor = ctx.composition.cursor_pos;
  glint_api()->free_context(&ctx);
  return written;
}

int glint_rime_commit_text(int64_t session, char *out, size_t out_len) {
  if (!glint_rime_session_alive(session)) {
    return -1;
  }
  // 同上：零初始化再设 data_size。
  RimeCommit commit = {0};
  RIME_STRUCT_INIT(RimeCommit, commit);
  if (!glint_api()->get_commit((RimeSessionId)session, &commit)) {
    return 0;  // 本次没有提交，不是错误
  }
  int written = copy_out(commit.text, out, out_len);
  glint_api()->free_commit(&commit);
  return written;
}

int64_t glint_rime_highlighted_index(int64_t session) {
  if (!glint_rime_session_alive(session)) {
    return -1;
  }
  // 零初始化，理由同 glint_rime_start：`RIME_STRUCT_INIT` 只设 data_size，
  // 未赋值的成员会是栈垃圾，而 librime 的 free_context 会按 data_size 处理它们。
  RIME_FLAVORED(RimeContext) ctx = {0};
  RIME_STRUCT_INIT(RIME_FLAVORED(RimeContext), ctx);
  if (!glint_api()->get_context((RimeSessionId)session, &ctx)) {
    return -1;
  }
  // RimeMenu 内的高亮是页内位置；外壳所有入口均使用全局索引。
  int64_t index = ctx.menu.num_candidates > 0
      ? (int64_t)ctx.menu.page_no * ctx.menu.page_size + ctx.menu.highlighted_candidate_index
      : -1;
  glint_api()->free_context(&ctx);
  return index;
}

// ------------------------------------------------------------------ 候选

int glint_rime_candidates_from(int64_t session, int64_t from, int limit,
                               GlintCandidateBatch *out) {
  if (out == NULL || limit <= 0) {
    return -1;
  }
  memset(out, 0, sizeof(*out));
  out->next_index = from;

  if (!glint_rime_session_alive(session)) {
    out->error = 1;
    return 0;
  }

  out->items = (GlintCandidate *)calloc((size_t)limit, sizeof(GlintCandidate));
  if (out->items == NULL) {
    out->error = 1;
    return -1;
  }

  RimeCandidateListIterator it;
  memset(&it, 0, sizeof(it));
  if (!glint_api()->candidate_list_from_index((RimeSessionId)session, &it, (int)from)) {
    // 该索引处没有候选。这是正常的「到此为止」，不是调用失败。
    out->at_end = 1;
    return 0;
  }

  int n = 0;
  for (;;) {
    // 复制文本：迭代器一旦推进，这里的指针就失效了。
    if (it.candidate.text != NULL) {
      out->items[n].text = strdup(it.candidate.text);
      out->items[n].comment =
          it.candidate.comment != NULL ? strdup(it.candidate.comment) : NULL;
      n++;
    }
    out->next_index = (int64_t)it.index + 1;

    if (n >= limit) {
      break;
    }
    if (!glint_api()->candidate_list_next(&it)) {
      out->at_end = 1;
      break;
    }
  }

  glint_api()->candidate_list_end(&it);
  out->count = n;
  return 0;
}

void glint_rime_free_batch(GlintCandidateBatch *batch) {
  if (batch == NULL || batch->items == NULL) {
    return;
  }
  for (int i = 0; i < batch->count; i++) {
    free(batch->items[i].text);
    free(batch->items[i].comment);
  }
  free(batch->items);
  batch->items = NULL;
  batch->count = 0;
}

// ------------------------------------------------------------------ 选择

int glint_rime_highlight(int64_t session, int64_t index) {
  if (!glint_rime_session_alive(session) || index < 0) {
    return 0;
  }
  return glint_api()->highlight_candidate((RimeSessionId)session, (size_t)index) ? 1 : 0;
}

int glint_rime_select(int64_t session, int64_t index) {
  if (!glint_rime_session_alive(session) || index < 0) {
    return 0;
  }
  return glint_api()->select_candidate((RimeSessionId)session, (size_t)index) ? 1 : 0;
}

void glint_rime_clear_composition(int64_t session) {
  if (glint_rime_session_alive(session)) {
    glint_api()->clear_composition((RimeSessionId)session);
  }
}

// ---------------------------------------------------------- 设置与词典维护
int glint_rime_schema_id(int64_t session, char *out, size_t capacity) {
  if (!glint_rime_session_alive(session)) return -1;
  return glint_api()->get_current_schema((RimeSessionId)session, out, capacity) ? 0 : -1;
}

int glint_rime_schema_value(const char *schema, const char *key, char *out, size_t capacity) {
  RimeConfig config = {0};
  if (!glint_api()->schema_open(schema, &config)) return -1;
  int result = glint_api()->config_get_string(&config, key, out, capacity) ? 0 : -1;
  glint_api()->config_close(&config);
  return result;
}

int glint_rime_get_option(int64_t session, const char *name) {
  if (!glint_rime_session_alive(session)) return -1;
  return glint_api()->get_option((RimeSessionId)session, name) ? 1 : 0;
}

int glint_rime_save_option(const char *name, int enabled) {
  // 当前设置页只管理这一项。绝不把任意界面字符串用作配置路径。
  if (strcmp(name, "ascii_punct") != 0) return -1;
  RimeConfig config = {0};
  if (!glint_api()->user_config_open("user", &config)) return -1;
  int result = glint_api()->config_set_bool(&config, "var/option/ascii_punct", enabled != 0) ? 0 : -1;
  glint_api()->config_close(&config);
  return result;
}

static RIME_FLAVORED(RimeLeversApi)* glint_levers(void) {
  RimeModule *module = glint_api()->find_module("levers_stdbool");
  if (!module || !module->get_api) return NULL;
  return (RIME_FLAVORED(RimeLeversApi)*)module->get_api();
}

int glint_rime_select_schema(int64_t session, const char *schema) {
  return glint_rime_session_alive(session) &&
    glint_api()->select_schema((RimeSessionId)session, schema) ? 0 : -1;
}

int glint_rime_user_dict_names(char *out, size_t capacity) {
  RIME_FLAVORED(RimeLeversApi)* api = glint_levers();
  if (!api || !out || capacity == 0) return -1;
  out[0] = '\0';
  RimeUserDictIterator iter = {0};
  if (!api->user_dict_iterator_init(&iter)) return 0;
  size_t length = 0;
  const char *name;
  while ((name = api->next_user_dict(&iter))) {
    size_t size = strlen(name);
    if (length + size + 2 > capacity) {
      api->user_dict_iterator_destroy(&iter);
      return -1;
    }
    memcpy(out + length, name, size);
    length += size;
    out[length++] = '\n';
    out[length] = '\0';
  }
  api->user_dict_iterator_destroy(&iter);
  return 0;
}

int glint_rime_backup_dict(const char *name) {
  RIME_FLAVORED(RimeLeversApi)* api = glint_levers();
  return api && api->backup_user_dict(name) ? 0 : -1;
}
int glint_rime_restore_dict(const char *file) {
  RIME_FLAVORED(RimeLeversApi)* api = glint_levers();
  return api && api->restore_user_dict(file) ? 0 : -1;
}
int glint_rime_export_dict(const char *name, const char *file) {
  RIME_FLAVORED(RimeLeversApi)* api = glint_levers();
  return api ? api->export_user_dict(name, file) : -1;
}
int glint_rime_import_dict(const char *name, const char *file) {
  RIME_FLAVORED(RimeLeversApi)* api = glint_levers();
  return api ? api->import_user_dict(name, file) : -1;
}
int glint_rime_user_sync_dir(char *out, size_t capacity) {
  if (!out || capacity == 0) return -1;
  glint_api()->get_user_data_sync_dir(out, capacity);
  return out[0] ? 0 : -1;
}

int glint_rime_validate_yaml(const char *text) {
  RimeConfig config = {0};
  int result = glint_api()->config_load_string(&config, text) ? 0 : -1;
  glint_api()->config_close(&config);
  return result;
}

int glint_rime_yaml_value(const char *text, const char *key, char *out, size_t capacity) {
  RimeConfig config = {0};
  int result = -1;
  if (glint_api()->config_load_string(&config, text))
    result = glint_api()->config_get_string(&config, key, out, capacity) ? 0 : -1;
  glint_api()->config_close(&config);
  return result;
}
int glint_rime_yaml_list(const char *text, const char *key, char *out, size_t capacity) {
  RimeConfig config = {0};
  if (!out || capacity == 0) return -1;
  out[0] = '\0';
  int result = -1;
  if (glint_api()->config_load_string(&config, text)) {
    size_t count = glint_api()->config_list_size(&config, key), used = 0;
    result = 0;
    for (size_t i = 0; i < count; ++i) {
      char path[1024], value[4096];
      int n = snprintf(path, sizeof(path), "%s/@%zu", key, i);
      if (n < 0 || (size_t)n >= sizeof(path) ||
          !glint_api()->config_get_string(&config, path, value, sizeof(value))) { result = -1; break; }
      size_t length = strlen(value);
      if (used + length + 2 > capacity) { result = -1; break; }
      memcpy(out + used, value, length); used += length;
      out[used++] = '\n'; out[used] = '\0';
    }
  }
  glint_api()->config_close(&config);
  return result;
}
