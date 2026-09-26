//
//  glint_rime.h
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

#ifndef GLINT_RIME_H
#define GLINT_RIME_H

#include <stddef.h>
#include <stdint.h>

/// librime C API 的桥接层。
///
/// 存在的理由有两条：
///
/// 1. **隔离不安全的指针操作。** librime 的 API 是函数指针表加一批需要手工
///    生命周期管理的结构体，直接在 Swift 里用会把这些细节散到各处。
///
/// 2. **不把 librime 的头文件暴露给 Swift。** 本头文件刻意不 include 任何
///    rime_*.h，会话用不透明的 int64_t 表示，因此 Swift 的桥接头只需要这一个
///    文件，Swift 侧完全看不到 RimeApi、RIME_STRUCT_INIT 这些东西。
///
/// 依据：[输入行为](../../docs/input-behavior.md) 约定
/// 用 `candidate_list_from_index` 读全局索引、`highlight_candidate` 移动高亮、
/// `select_candidate` 确认，且**只由 Rime 决定候选顺序与提交结果**。

#ifdef __cplusplus
extern "C" {
#endif

/// 一个候选的**自有副本**。
///
/// text / comment 指向本层自己分配的内存，一直有效到 `glint_rime_free_batch`。
/// 之所以必须复制：librime 的候选文本位于迭代器当前位置的临时缓冲，
/// 迭代推进或结束即失效，不能当长期 UI 数据保存
/// （见功能方案 §6.3 对参考实现的说明）。
typedef struct {
  char *text;
  char *comment;  // 可能为 NULL
} GlintCandidate;

/// 从某个全局索引开始读到的一批候选。
typedef struct {
  GlintCandidate *items;
  int count;
  /// 继续读取时应传入的全局索引。仅当 at_end 为 0 时才有意义。
  int64_t next_index;
  /// 1 表示已到末尾，没有更多候选。
  int at_end;
  /// 非 0 表示调用失败，此时 count / at_end 都不可信——
  /// **不能把失败当作「没有更多」**（功能方案 §6.2）。
  int error;
} GlintCandidateBatch;

/// 初始化 librime。
///
/// `user_data_dir` 与 `shared_data_dir` 必须指向**隔离的**目录，
/// 不能是用户正在使用的 `~/Library/Rime`。
/// 返回 0 表示成功。
int glint_rime_start(const char *app_name,
                     const char *user_data_dir,
                     const char *shared_data_dir,
                     const char *log_dir);

/// 结束维护线程并释放引擎。重复调用无副作用。
void glint_rime_finalize(void);

/// 阻塞到部署完成。用于测试与安装后的首次部署。
/// 返回 0 表示成功。
int glint_rime_deploy(void);

/// librime 版本串，形如 "1.17.0"。只读，无需释放。
const char *glint_rime_version(void);

/// 创建 / 销毁会话。返回 0 表示失败。
int64_t glint_rime_create_session(void);
void glint_rime_destroy_session(int64_t session);
/// 会话是否仍然有效。用于丢弃失效会话的迟到事件。
int glint_rime_session_alive(int64_t session);

/// 把一次按键交给引擎。keycode / mask 沿用系统的定义。
/// 返回 1 表示引擎已处理该按键，外壳不应对它再做别的事。
int glint_rime_process_key(int64_t session, int keycode, int mask);

/// 引擎当前的输入串（尚未转换的编码），只读，可能为 NULL。
const char *glint_rime_get_input(int64_t session);

/// 预编辑文本（已转换部分 + 剩余编码）。写入 out，返回写入字节数，-1 表示失败。
int glint_rime_get_preedit(int64_t session, char *out, size_t out_len, int *cursor);
size_t glint_rime_caret_pos(int64_t session);

/// 取出**并消费**引擎的提交结果。
///
/// 返回写入字节数，0 表示本次没有提交。**调用一次就要消费一次**，
/// 否则会重复上屏（功能方案 §6.4）。
int glint_rime_commit_text(int64_t session, char *out, size_t out_len);

/// 引擎当前高亮的全局候选索引；-1 表示不可用。
int64_t glint_rime_highlighted_index(int64_t session);

/// 从全局索引 `from` 开始读最多 `limit` 个候选到 `out`。
/// 返回 0 表示调用本身成功（结果的可靠性另看 out->error）。
int glint_rime_candidates_from(int64_t session, int64_t from, int limit,
                               GlintCandidateBatch *out);

/// 释放 `glint_rime_candidates_from` 分配的内存。
void glint_rime_free_batch(GlintCandidateBatch *batch);

/// 移动高亮，**不提交**。返回 1 表示成功。
///
/// 注意：返回 0 可能只是位置没变化，不代表失败——不能据此强制选首项
/// （功能方案 §6.3）。
int glint_rime_highlight(int64_t session, int64_t index);

/// 确认某个全局索引的候选。返回 1 表示成功。
int glint_rime_select(int64_t session, int64_t index);

/// 当前方案与已编译方案字段。字符串写入 out，失败返回 -1。
int glint_rime_validate_yaml(const char *text);
int glint_rime_yaml_value(const char *text, const char *key, char *out, size_t capacity);
int glint_rime_yaml_list(const char *text, const char *key, char *out, size_t capacity);
int glint_rime_schema_id(int64_t session, char *out, size_t capacity);
int glint_rime_schema_value(const char *schema, const char *key, char *out, size_t capacity);
int glint_rime_get_option(int64_t session, const char *name);
/// 仅改变当前会话，不保存用户配置。
void glint_rime_set_option(int64_t session, const char *name, int enabled);
/// 使用 Rime 自己的 user.yaml 保存开关；调用方只允许受支持的选项。
int glint_rime_save_option(const char *name, int enabled);

/// YAML 转 JSON，供配置补丁合并使用。返回字符串由 free 释放。
char *glint_yaml_json(const char *text);
int glint_rime_select_schema(int64_t session, const char *schema);

/// 维护时必须先关闭全部 session。实际合并、快照与文本转换由 Rime levers 执行。
int glint_rime_user_dict_names(char *out, size_t capacity);
int glint_rime_backup_dict(const char *name);
int glint_rime_restore_dict(const char *file);
int glint_rime_export_dict(const char *name, const char *file);
int glint_rime_import_dict(const char *name, const char *file);
int glint_rime_user_sync_dir(char *out, size_t capacity);

/// 取消当前组合，不删除已上屏文字。
void glint_rime_clear_composition(int64_t session);

#ifdef __cplusplus
}
#endif

#endif  // GLINT_RIME_H
