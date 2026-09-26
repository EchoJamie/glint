// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
#include "glint_rime.h"
#include <yaml.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void json_string(FILE *stream, const unsigned char *text, size_t length) {
  fputc('"', stream);
  for (size_t i = 0; i < length; ++i) {
    unsigned char ch = text[i];
    if (ch == '"' || ch == '\\') { fputc('\\', stream); fputc(ch, stream); }
    else if (ch < 32) fprintf(stream, "\\u%04x", ch);
    else fputc(ch, stream);
  }
  fputc('"', stream);
}

static int emit(FILE *stream, yaml_document_t *document, yaml_node_t *node, int depth, int *budget) {
  if (!node || depth > 64 || --*budget < 0) return -1;
  if (node->type == YAML_SCALAR_NODE) {
    const char *value = (const char*)node->data.scalar.value;
    int null_value = !strcmp((char*)node->tag, YAML_NULL_TAG) ||
      (node->data.scalar.style == YAML_PLAIN_SCALAR_STYLE &&
       (!*value || !strcmp(value, "~") || !strcasecmp(value, "null")));
    if (null_value) fputs("null", stream);
    else json_string(stream, node->data.scalar.value, node->data.scalar.length);
  } else if (node->type == YAML_SEQUENCE_NODE) {
    fputc('[', stream);
    for (yaml_node_item_t *item = node->data.sequence.items.start; item < node->data.sequence.items.top; ++item) {
      if (item != node->data.sequence.items.start) fputc(',', stream);
      if (emit(stream, document, yaml_document_get_node(document, *item), depth + 1, budget)) return -1;
    }
    fputc(']', stream);
  } else if (node->type == YAML_MAPPING_NODE) {
    fputc('{', stream);
    for (yaml_node_pair_t *pair = node->data.mapping.pairs.start; pair < node->data.mapping.pairs.top; ++pair) {
      yaml_node_t *key = yaml_document_get_node(document, pair->key);
      if (!key || key->type != YAML_SCALAR_NODE) return -1;
      for (yaml_node_pair_t *prior = node->data.mapping.pairs.start; prior < pair; ++prior) {
        yaml_node_t *other = yaml_document_get_node(document, prior->key);
        if (other && other->type == YAML_SCALAR_NODE && !strcmp((char*)key->data.scalar.value, (char*)other->data.scalar.value)) return -1;
      }
      if (pair != node->data.mapping.pairs.start) fputc(',', stream);
      json_string(stream, key->data.scalar.value, key->data.scalar.length); fputc(':', stream);
      if (emit(stream, document, yaml_document_get_node(document, pair->value), depth + 1, budget)) return -1;
    }
    fputc('}', stream);
  } else return -1;
  return 0;
}

char *glint_yaml_json(const char *text) {
  if (!text || strlen(text) > 4 * 1024 * 1024) return NULL;
  yaml_parser_t parser; yaml_document_t document;
  if (!yaml_parser_initialize(&parser)) return NULL;
  yaml_parser_set_input_string(&parser, (const unsigned char*)text, strlen(text));
  if (!yaml_parser_load(&parser, &document)) { yaml_parser_delete(&parser); return NULL; }
  char *result = NULL; size_t size = 0; int budget = 100000;
  FILE *stream = open_memstream(&result, &size);
  int status = stream ? emit(stream, &document, yaml_document_get_root_node(&document), 0, &budget) : -1;
  if (stream && fclose(stream) != 0) status = -1;
  yaml_document_delete(&document);
  // 拒绝多文档，不能静默丢掉后面的用户配置。
  if (!yaml_parser_load(&parser, &document)) status = -1;
  else { if (yaml_document_get_root_node(&document)) status = -1; yaml_document_delete(&document); }
  yaml_parser_delete(&parser);
  if (status) { free(result); return NULL; }
  return result;
}
