#!/bin/bash
# @file Entry
# @brief ホストエントリを管理するライブラリ
# @description 
source "$IPAM_SHELL_LIB/Utils.sh"

# Default
IPAM_ENTRY_FILE="${IPAM_ENTRY_FILE:-/var/ipam-shell/entry.tsv}"
SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["ls"]="ListEntry"
SUB_CMD_LIST["add"]="AddEntry"
SUB_CMD_LIST["rm"]="RemoveEntry"
################################################################################
# @descirption 【内部関数】エントリ情報の出力
# @env UUID エントリのUUID
# @env NAME エントリ名
# @env WHAT エントリの説明
# @return 0 正常終了
printEntry(){
    set +u
    echo "-----"
    echo "Information:"
    echo "  - UUID: \"${UUID}\""
    echo "  - Entry Name: \"${NAME}\""
    echo "  - Description: \"${WHAT}\""
    echo "-----"
    set -u
    return 0
}
################################################################################
# @descirption 【内部関数】UUIDからエントリを検索し、対象を返します
# @env UUID エントリのUUID
# @set HITLINENO ヒットした行番号
# @set HITUUID ヒットしたエントリのUUID
# @set HITNAME ヒットしたエントリ名
# @set HITWHAT ヒットしたエントリの説明
# @return 0 正常終了
# @return 1 異常終了（指定されたUUIDが見つからないか、重複したエントリがある）
getEntry(){

  if ! result=$(LC_ALL=C grep -Fn "${UUID}" <(cut -d$'\t' -f1 "$IPAM_ENTRY_FILE"));then
    echo "Error: Specific UUID is not found." 1>&2
    return 1
  fi

  HITLINENO="${result%%:*}"
  IFS=$'\t' read -r HITUUID HITNAME HITWHAT <<< "${result#*:}"

  if [[ $(echo "${result}" | wc -l ) -ge 2 ]];then
    echo "Error: Specific UUID duplicated. Matched line: ${HITLINENO}"
    exit 1
  fi

  unset hitLineNum result
  export HITLINENO HITUUID HITNAME HITWHAT
  return 0
}
################################################################################
# @descirption 【内部関数】エントリ名からエントリを検索し、対象を返します
# @env NAME エントリ名
# @set HITLINENO ヒットした行番号
# @set HITUUID ヒットしたエントリのUUID
# @set HITNAME ヒットしたエントリ名
# @set HITWHAT ヒットしたエントリの説明
# @return 0 正常終了（エントリのある行番号の変数HITLINENOおよび対象のエントリHITUUID、HITNAME、HITWHAT返します）
# @return 1 異常終了（指定されたエントリ名が見つからない）
getEntryByName(){
  if ! result=$(LC_ALL=C grep -Fn $'\t'"${NAME}"$'\t' "$IPAM_ENTRY_FILE");then
    return 1
  fi

  HITLINENO="${result%%:*}"
  IFS=$'\t' read -r HITUUID HITNAME HITWHAT <<< "${result#*:}"

  unset result
  export HITLINENO HITUUID HITNAME HITWHAT
  return 0
}
########################################################################################
# @descirption 【内部関数】エントリのUUIDとエントリ名の連想配列を生成する内部関数
# @arg $1 連想配列とする変数名（declare -A）
# @return 0 正常終了
generateUUidNameArray(){
  while IFS=$'\t' read -r id name what;do
    : "$what"
    eval "${1}[\"$id\"]=\"$name\" "
  done < "$IPAM_ENTRY_FILE"
  return 0
}
################################################################################
# @description エントリの一覧
# @return 0 正常終了
ListEntry(){

  # データを詰め込むようの一時的なストリームを作成
  data="$(mktemp -u)"
  mkfifo "$data"

  if [[ "${1:-}" == "-l" ]];then
    # -l をつけるとUUID全部表示
    while IFS=$'\t' read -r id name desc;do
      echo -e "${id}\t$name\t${desc}";
    done < "$IPAM_ENTRY_FILE" > "$data" &
  else
    # -l なしだとUUID短くする
    while IFS=$'\t' read -r id name desc;do
      echo -e "${id%%-*}\t$name\t${desc}";
    done < "$IPAM_ENTRY_FILE" > "$data" &
    echo "* Tips: 'ipam entry ls -l' shown all uuid."
  fi

  cat <(echo -e "UUID\tNAME\tDescription") "$data" | column -ts $'\t'
  rm "$data"
}

################################################################################
# @descirption エントリの追加
# @arg $1 string エントリ名
# @arg $2 string エントリの説明
# @set UUID 追加したエントリのUUID
# @set NAME 追加したエントリ名
# @set WHAT 追加したエントリの説明
# @return 0 正常終了
AddEntry(){

  if [[ $# -ne 2 ]];then
    echo "usage: ipam entry add [name] [description]"
    return 1
  fi

  NAME="$1"
  WHAT="$2"

  if getEntryByName;then
    echo "Error: Same Name Entry exist."
    printEntry
    return 1
  fi


  UUID="$(uuidgen)"

  if ! echo -e "${UUID}\t${NAME}\t${WHAT}" >> "$IPAM_ENTRY_FILE";then
    echo "Error: Failed to add entry...($NAME, $UUID)"
  fi

  echo "entry \"$NAME\" ($UUID) created."
  export UUID NAME WHAT
  return 0
}
################################################################################
# @description エントリの削除
# @arg $1 削除対象のエントリ名
# @return 0 正常終了
# @return 0 異常終了
RemoveEntry(){
  
  if [[ $# -ne 1 ]];then
    echo "usage: ipam entry del [name]"
    return 1
  fi

  NAME="$1"

  if ! getEntryByName;then
    echo "Error: Entry \"$NAME\" is not found."
    return 1
  fi

  echo "Target Found:"
  echo "  - Entry: \"$NAME\" ($UUID)"
  echo "  - Description: \"$WHAT\""

  askDelete || return 1

  # 削除
  deleteLine "${HITLINENO}" "${IPAM_ENTRY_FILE}" || return 1
  unset HITLINENO
  return 0

}

