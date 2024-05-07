#!/bin/bash -eu
# @file IPAM.
# @brief IPアドレスを管理するためのライブラリ
# @description 
source "$IPAM_SHELL_LIB/Utils.sh"

IPAM_IPADDRESS_FILE="${IPAM_IPADDRESS_FILE:-/var/ipam-shell/ipaddress.tsv}"
SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["ls"]="ListIpAddress"
SUB_CMD_LIST["assign"]="AssignIpAddress"
SUB_CMD_LIST["release"]="ReleaseIpAddress"
################################################################################
# @description 【内部関数】割当済みのIPアドレスか確認
# @env IP_ADDRESS 対象のIPアドレス
# @return 0 割当済み（対象の行：HITLINENO）
# @return 1 未割り当て
isAssignedIp(){
  if ! result=$(LC_ALL=C grep -nF $'\t'"${IP_ADDRESS}"$'\t' "$IPAM_IPADDRESS_FILE");then
    return 1 # no reserve, resource is available.
  fi

  if [[ $(echo "${result}" | wc -l ) -ge 2 ]];then
    echo "Error: IPAddress Entry duplicated. Match line: ${result}"
    exit 1
  fi

  HITLINENO="${result%%:*}"
  IFS=$'\t' read -r HITUUID HITIPADDRESS HIT_DNSHOSTNAME HIT_PTR_BOOL <<< "${result#*:}"

  export HITUUID HITLINENO HITIPADDRESS HIT_DNSHOSTNAME HIT_PTR_BOOL
  return 0
}
################################################################################
# @description 予約済みのIPエントリの一覧
# @return 0 正常終了
ListIpAddress(){
  source "$IPAM_SHELL_LIB/Entry.sh"
  set +u

  # ホストエントリのUUIDとエントリ名を参照
  declare -A names
  generateUUidNameArray names

  # データを詰め込むようの一時的なストリームを作成
  data="$(mktemp -u)"
  mkfifo "$data"

  if [[ "${1:-}" == "-l" ]];then
    # -l をつけるとUUID全部表示
    while IFS=$'\t' read -r id ip desc;do
        echo -e "${id}\t\t${ip}\t${desc}"
    done < "$IPAM_IPADDRESS_FILE" > "$data" &
  else
    # -l なしだとUUID短くする
    while IFS=$'\t' read -r id ip desc;do
        echo -e "${id%%-*}\t${names[${id}]}\t${ip}\t${desc}"
    done < "$IPAM_IPADDRESS_FILE" > "$data" &
    echo "* Tips: 'ipam ip ls -l' shown all uuid."
  fi

  cat <(echo -e "UUID\tNAME\tIP_ADDRESS\tDNS HOSTNAME\tENABLE_REV_RECORD") "$data" | column -ts $'\t'
  rm "$data"

  return 0
}
################################################################################
# @description IPアドレスの割当
# @arg $1 ホストエントリ名
# @arg $2 割り当てるIPアドレス
# @return 0 割当完了（もしくは割当済み）
# @return 1 割当不可（他のホストで割当済み、ホストが存在しないなど）
AssignIpAddress(){
  if [[ $# -ne 2 ]] && [[ $# -ne 3 ]];then
    echo "usage: ipam ip assign [name] [ip] [hostname default=name]"
    return 1
  fi

  NAME="$1"
  IP_ADDRESS="$2"

  source "$IPAM_SHELL_LIB/Entry.sh"

  if ! getEntryByName;then
    echo " Error: Entry \"$NAME\" is not exist"
    return 1
  fi
  UUID="$HITUUID"

  if isAssignedIp;then
    if [[ "$HITUUID" == "$UUID" ]];then
      echo "INFO: Already assigned"
      return 0
    fi
    echo "Error: Already assigned Another Entry(UUID=$HITUUID)"
    UUID=$HITUUID getEntry
    printEntry
    return 1
  fi

  if ! echo -e "$UUID\t${IP_ADDRESS}\t${NAME}\tFALSE" >> "${IPAM_IPADDRESS_FILE}";then
    echo "Error: Failed to add entry..."
  fi
  return 0
}
################################################################################
# @description IPアドレスの開放
# @arg $1 対象のIPアドレス
# @return 0 開放完了
# @return 1 開放不可（未割当、もしくは不正なIPアドレス指定）

ReleaseIpAddress(){

  if [[ $# -ne 1 ]];then
    echo "usage: ipam ip release [ip]"
    return 1
  fi

  IP_ADDRESS="$1"
  if ! isAssignedIp;then
    echo "IP not reserved or, invalid ip IP_ADDRESS=\"$IP_ADDRESS\""
    return 1
  fi
  echo "Found $HITIPADDRESS($HITUUID, $HIT_DNSHOSTNAME)"
  
  #askDelete || return 1

  # 削除
  deleteLine "${HITLINENO}" "${IPAM_IPADDRESS_FILE}" || return 1
  unset HITLINENO
  return 0

  unset HITLINENO
}
