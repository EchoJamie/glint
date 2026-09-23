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

#include <stdlib.h>
#include <string.h>

/// librime 的函数指针表。rime_get_api_stdbool() 返回进程内单例，取一次即可。
static const RIME_FLAVORED(RimeApi) *glint_api(void) {
  static const RIME_FLAVORED(RimeApi) *api = NULL;
  if (api == NULL) {
    api = rime_get_api_stdbool();
  }
  return api;
}

// ---------------------------------------------------------------- 生命周期

int glint_rime_start(const char *app_name,
                     const char *user_data_dir,
                     const char *shared_data_dir,
                     const char *log_dir) {
  if (user_data_dir == NULL || shared_data_dir == NULL) {
    return -1;
  }

  RimeTraits traits;
  RIME_STRUCT_INIT(RimeTraits, traits);
  traits.shared_data_dir = shared_data_dir;
  traits.user_data_dir = user_data_dir;
  traits.log_dir = log_dir;
  traits.distribution_name = "流光";
  traits.distribution_code_name = "Glint";
  traits.distribution_version = "0.1.0";
  // "rime." 前缀便于 librime 清理旧日志。
  traits.app_name = app_name;

  glint_api()->setup(&traits);
  // 传 NULL 表示沿用 setup 里给的 traits。
  glint_api()->initialize(NULL);
  return 0;
}

void glint_rime_finalize(void) {
  glint_api()->join_maintenance_thread();
  glint_api()->finalize();
}

int glint_rime_deploy(void) {
  if (!glint_api()->start_maintenance(True)) {
    return -1;
  }
  glint_api()->join_maintenance_thread();
  return 0;
}

const char *glint_rime_version(void) { return glint_api()->get_version(); }

// ------------------------------------------------------------------ 会话

int64_t glint_rime_create_session(void) {
  return (int64_t)glint_api()->create_session();
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

int glint_rime_get_preedit(int64_t session, char *out, size_t out_len) {
  if (!glint_rime_session_alive(session)) {
    return -1;
  }
  RIME_FLAVORED(RimeContext) ctx;
  RIME_STRUCT_INIT(RIME_FLAVORED(RimeContext), ctx);
  if (!glint_api()->get_context((RimeSessionId)session, &ctx)) {
    return -1;
  }
  int written = copy_out(ctx.composition.preedit, out, out_len);
  glint_api()->free_context(&ctx);
  return written;
}

int glint_rime_commit_text(int64_t session, char *out, size_t out_len) {
  if (!glint_rime_session_alive(session)) {
    return -1;
  }
  RimeCommit commit;
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
  RIME_FLAVORED(RimeContext) ctx;
  RIME_STRUCT_INIT(RIME_FLAVORED(RimeContext), ctx);
  if (!glint_api()->get_context((RimeSessionId)session, &ctx)) {
    return -1;
  }
  int64_t index = (int64_t)ctx.menu.highlighted_candidate_index;
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
