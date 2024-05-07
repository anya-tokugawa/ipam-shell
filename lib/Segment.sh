#!/bin/bash
# @file Segment
# @brief A library that store segment
# @description 
source "$IPAM_SHELL_LIB/Utils.sh"

# @descirption ADD New Segment
# @arg $1 string Entry name
# @env UUID needed.
# @return 0 hit with HIT_LINENO(numeric)
# @return 1 not found

# Default
IPAM_SEG_FILE="${IPAM_SEG_FILE:-/var/ipam-shell/segment.tsv}"
SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["ls"]="ListSegment"
SUB_CMD_LIST["add"]="AddSegment"
SUB_CMD_LIST["rm"]="RemoveSegment"
SUB_CMD_LIST["connect"]="ConnectDomain"
################################################################################
# @description 【内部関数】セグメント名からセグメントのエントリを検索し、エントリを取得する
# @env CIDR 対象のセグメント
checkNewSegment(){
  if ! grepcidr "${CIDR}" <(cut -d$'\t' -f2 "${IPAM_SEG_FILE}");then
    return 0 # New.
  else
    return 1 # Already exist included CIDR range. or no expected ip address pattern
  fi
}
################################################################################
# @description 【内部関数】エントリの重複チェック
# @return 0 重複なし
# @exitcode 1 重複あり
# @stderr エラーメッセージ
checkDuplicate(){
  if [[ $(echo "${1}" | wc -l ) -ge 2 ]];then
    echo "Error: CIDR duplicated. match line: ${HITLINENO}" 1>&2
    exit 1
  fi
  return 0
}
################################################################################
# @description 【内部関数】セグメント情報を表示
# @stdout セグメント情報
printSegment(){
    echo "-----"
    echo "Information:"
    echo "  - NAME: \"${NAME}\""
    echo "  - CIDR: \"${CIDR}\""
    echo "  - Description: \"${WHAT}\""
    echo "-----"
}
################################################################################
# @description 【内部関数】CIDRからセグメントのエントリを検索する
# @env CIDR 対象のセグメント
# @set HITLINENO エントリの行
# @return 0 正常終了
# @return 1 異常終了（CIDRから一致するエントリなし、もしくは重複エントリあり）
searchSegmentByCidr(){
  if ! data=$(LC_ALL=C grep -nx "${CIDR}" <(cut -d$'\t' -f2 "$IPAM_SEG_FILE"));then
    return 1
  fi
  checkDuplicate "$data" || return 1
  export HITLINENO="${data%%:*}"
  return 0
}
################################################################################
# @description 【内部関数】CIDRからセグメントのエントリを検索し、エントリを取得する
# @env CIDR 対象のセグメント
# @set HITNAME セグメント名
# @set HITCIDR セグメント
# @set HITWHAT エントリの説明
# @return 0 正常終了
# @return 1 異常終了（CIDRから一致するエントリなし、もしくは重複エントリあり）
getSegmentByCidr(){
  if ! data=$(LC_ALL=C grep -P '^.*?\\t'"${CIDR}" <(cut -d$'\t' -f1 "$IPAM_SEG_FILE"));then
    return 1
  fi
  checkDuplicate "$data" || return 1
  IFS=$'\t' read -r HITNAME HITCIDR HITWHAT HITDOMAIN <<< "$data"
  unset data
  export HITNAME HITCIDR HITWHAT HITDOMAIN
  return 0
}
################################################################################
# @description 【内部関数】セグメント名からセグメントのエントリを検索し、エントリを取得する
# @env CIDR 対象のセグメント
# @set HITNAME セグメント名
# @set HITCIDR セグメント
# @set HITWHAT エントリの説明
# @return 0 正常終了
# @return 1 異常終了（セグメント名から一致するエントリなし、もしくは重複エントリあり）
getSegmentByName(){
  if ! data=$(LC_ALL=C grep -F "${NAME}"$'\t' "$IPAM_SEG_FILE");then
    return 1
  fi
  checkDuplicate "$data" || return 1
  IFS=$'\t' read -r HITNAME HITCIDR HITWHAT HITDOMAIN <<< "$data"
  unset data
  export HITNAME HITCIDR HITWHAT HITDOMAIN
  return 0
}
################################################################################
getCidrByDomain(){
  if ! data=$(LC_ALL=C grep -P "$(echo "$NAME" | sed 's;\.;\.;g')$" "$IPAM_SEG_FILE");then
    return 1
  fi
  IFS=$'\t' read -r _ HITCIDR _ _ <<< "$data"
  export HITCIDR
  unset _
}
################################################################################
# @description セグメント一覧表示
ListSegment(){
  cat <(echo -e "NAME\tCIDR\tDescription\tConnected Domain") "$IPAM_SEG_FILE" | column -ts $'\t' 
}
################################################################################
# @descirption セグメントの追加
# @arg $1 string エントリ名
# @arg $2 string エントリに属するCIDR
# @arg $2 string エントリの説明
AddSegment(){

  if [[ $# -ne 3 ]];then
    echo "usage: ipam segment add [name] [x.x.x.x/x] [description]"
    exit 1
  fi

  NAME="$1"
  CIDR="$2"
  WHAT="$3"

  if ! grep -qP '(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])' <<< "$CIDR";then
    echo "Error: Invalid CIDR - \"$CIDR\"" 1>&2
    return 1
  fi

  if getSegmentByName;then
    echo "Error: Same Name Entry exist." 1>&2
    NAME=$HITNAME CIDR=$HITCIDR WHAT=$HITCIDR printSegment 1>&2
    return 1
  fi

  if ! result="$(checkNewSegment)";then
    echo "Error: Included Segment Exist."
    echo "----"
    echo "Detected Segements:"
    echo "$result"
    return 1
  fi

  if echo -e "${NAME}\t${CIDR}\t${WHAT}" >> "$IPAM_SEG_FILE";then
    echo "Info: Successfly added Segment - $NAME($CIDR)"
else
    echo "Warn: Failed to add Segment - $NAME($CIDR)"
  fi
  export NAME CIDR WHAT
}
################################################################################
# @description セグメントの削除
# @arg $1 対象セグメント
RemoveSegment(){

  if [[ $# -ne 2 ]];then
    echo "usage: ipam segment rm [x.x.x.x/x]"
    exit 1
  fi

  CIDR="$2" 
  searchSegmentByCidr || return 1
  getSegmentByName || return 1

  echo "Target Found:"
  echo "  - Name: \"$HITNAME\" ($HITCIDR)"
  echo "  - Description: \"$HITWHAT\""

  askDelete || return 1

  # 削除
  deleteLine "${HITLINENO}" "${IPAM_SEG_FILE}" || return 1
  unset HITLINENO
  return 0
}
################################################################################
ConnectDomain(){
  if [[ $# -ne 2 ]];then
    echo "usage: ipam segment connect [x.x.x.x/x] [domain]"
    exit 1
  fi
  CIDR="$1"
  DOMAIN="$2"

  source "$IPAM_SHELL_LIB/Zone.sh"
  NAME="$DOMAIN"
  if ! getZone;then
    echo "Error: Zone Not Found." 1>&2
    exit 1
  fi

  # NOTE: get HITLINENO
  if ! searchSegmentByCidr;then
    echo "Error: Segment Not Found." 1>&2
    exit 1
  fi

  if ! sed -i "${HITLINENO}s;^\\(.*\\)$;\\1\t${DOMAIN};" "$IPAM_SEG_FILE";then
   echo "Error: can not write file..."
   exit 1
 fi

  

}
disconnectDomain(){
  :
}
