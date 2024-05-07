#!/bin/bash
# @file Cli
# @brief サブコマンドを呼び出す為の再帰的なライブラリ
# @description
# IPAMコマンド配下のentryやipやsegmentといったサブコマンドや
# 配下のサブコマンド（e.g. ls, add, rm）などを呼び出すためのユーティリティ


# @description サブコマンドの呼び出しをするラッパー関数
# @arg $1 string サブコマンド以前のコマンド列
# @arg $2 string サブコマンドが定義されたファイル（SUB_CMD_TYPE="FILE"）
# @arg $3 string サブコマンド名
# @arg $4 string 以降は引数
# @return 0 正常終了
# @return 1 異常終了（コマンドが見つからないか、指定されていないか、サブコマンド定義ファイルが誤っているか）
CallSubCmd(){
  PREFIX_CMDS="${1:-}"
  SUBCMD_FILE="${2:-}"
  shift 2
  

  declare -A SUB_CMD_LIST=()
  SUB_CMD_TYPE=""

  # Load SubCmd Configuration
  # e.g. Entry.sh, Segment.sh...
  source "$SUBCMD_FILE"

  # If not specify SubCmd
  if [[ "" == "${1:-}" ]];then
    echo "Error: SUBCMD is not specifed."
    SUB_CMDS_STR="${!SUB_CMD_LIST[*]}"
    echo "usage: $PREFIX_CMDS [${SUB_CMDS_STR// /|}]"
    return 1
  fi

  # Invalid SUB_CMD_TYPE
  if [[ "$SUB_CMD_TYPE" != "FUNC" ]] && [[ "$SUB_CMD_TYPE" != "FILE" ]];then
    echo "Error: [$SUBCMD_FILE] SUB_CMD_TYPE=\"$SUB_CMD_TYPE\" invalid or undefined."
    return 1
  fi

  # Search SubCmd
  for name in "${!SUB_CMD_LIST[@]}";do

    if [[ "$1" == "$name" ]];then
      # Pass over subcmd only.
      PREFIX_CMDS="$PREFIX_CMDS $1"
      shift

      case "$SUB_CMD_TYPE" in

        "FUNC")
          # A type 'FUNC' will executing FUNCTION with arguments.
          ${SUB_CMD_LIST[$name]} "$@" # execute subcmd
          return 0;;

        "FILE")
          # A type 'FILE' will loading FILE with and searching next subcmd.
          CallSubCmd "$PREFIX_CMDS" "${SUB_CMD_LIST[$name]}" "$@" # nested
          return 0;;
      esac
    fi
  done

  # If specified subcmd not found 
  echo "Error: No expected subcmd: $PREFIX_CMDS $SUBCMD_NAME"
  SUB_CMDS_STR="${!SUB_CMD_LIST[*]}"
  echo "usage: $PREFIX_CMDS [${SUB_CMDS_STR// /|}]"
  return 1
}
