//
//  BridgingHeader.h
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

#ifndef GLINT_BRIDGING_HEADER_H
#define GLINT_BRIDGING_HEADER_H

/// Swift 只看到 glint_rime 这层封装。
///
/// 刻意**不**在这里 include librime 的 rime_api.h：librime 的类型和
/// 函数指针表全部关在 glint_rime.c 里，Swift 侧既不需要它的头文件路径，
/// 也不会误用那些需要手工管理生命周期的结构体。
#include "rime/glint_rime.h"

#endif  // GLINT_BRIDGING_HEADER_H
