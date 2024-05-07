#!/bin/bash
set -eu
# @file Zone
source "$IPAM_SHELL_LIB/Utils.sh"

# Default
IPAM_ZONE_FILE="${IPAM_ZONE_FILE:-/var/ipam-shell/zone.tsv}"
SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["ls"]="ListZone"
SUB_CMD_LIST["create"]="createZone"
SUB_CMD_LIST["delete"]="deleteZone"
SUB_CMD_LIST["edit"]="editZone"

# @description SOAレコードの発行
# @env NAME ゾーン名
printSoa(){
  getZone || return 1
  echo "\$TTL $TTL @ IN SOA $CONTACT  ( $SERIAL; $REFRESH_SEC; $RETRY_SEC; $EXPIRE_SEC; $MINIMUM_SEC; )"
}

# @description ゾーンの一致検索
# @env NAME ゾーン名
searchZone(){
  if ! DATA=$(LC_ALL=C grep -nxF "${NAME}" <(cut -d$'\t' -f1 "$IPAM_ZONE_FILE"));then
    return 1
  fi

  hitLineNum=$(echo "${DATA}" | wc -l ) 
  if [[ $hitLineNum -ge 2 ]];then
    echo "Error: searchZone - Zone duplicated. Match line: ${DATA%%:*}"
    exit 1
  fi
  unset hitLineNum
  export DATA
}

# @description ゾーンの行番号取得
# @env NAME ゾーン名
getLineNumberOfZone(){
  if ! searchZone;then
    return 1
  fi
  HITLINENO="${DATA%%:*}"
  export HITLINENO
}

# @description ゾーン情報とSOAレコード情報の取得
# @env NAME ゾーン名
getZone(){
  getLineNumberOfZone ||  return 1
  DATA="$(sed -n "${HITLINENO}p" "$IPAM_ZONE_FILE")"
  IFS=$'\t' read -r NAME WHAT SERIAL CONTACT TTL REFRESH_SEC RETRY_SEC EXPIRE_SEC MINIMUM_SEC <<< "$DATA"
  export NAME WHAT SERIAL CONTACT TTL REFRESH_SEC RETRY_SEC EXPIRE_SEC MINIMUM_SEC
  unset DATA
  return 0
}

# @description 既知のゾーン情報の確認
checkNewZone(){
  searchZone && return 1 || return 0
  # ゾーンがなければ true
}

listZoneName(){
  cut -d$'\t' -f1 "$IPAM_ZONE_FILE"
}

###############################

# @description ゾーンの一覧表示
ListZone(){
  cat <(echo -e "ZONE\tDescription\tSERIAL\tCONTACT\tTTL\tREFRESH\tRETRY\tEXPIRE\tMININUM") "$IPAM_ZONE_FILE" | column -ts $'\t' 
}

# @descirption ゾーンの新規作成
# @arg $1 string ゾーン名
# @arg $2 string ゾーンの説明
# @return 0 作成完了
# @return 1 作成不可
createZone(){

  if [[ $# -ne 2 ]];then
    echo "usage: ipam zone create [zone] [description]"
    exit 1
  fi

  NAME="$1"
  WHAT="$2"

  # e.g. www.example.com.
  VALID_DNS_ZONE="^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])\.$"

  if ! grep -qP "$VALID_DNS_ZONE" <<< "$NAME";then
    echo "Error: Invalid Zone ZONE=\"$NAME\""
    exit 1
  fi

  if getZone;then
    # exist
    echo "Error: Same Zone exist."
    echo "  - Zone: $NAME"
    echo "  - Description: $WHAT"
    return 1
  fi

  ############################################
  TTL="3600000"
  CONTACT="root.${NAME}"
  SERIAL="$(date +'%Y%m%d')00"
  REFRESH_SEC="1h"
  RETRY_SEC="20h"
  EXPIRE_SEC="30d"
  MINIMUM_SEC="5m"
  ############################################

  if ! printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$NAME" "$WHAT" "$SERIAL" "$CONTACT" "$TTL" "$REFRESH_SEC" "$RETRY_SEC" "$EXPIRE_SEC" "$MINIMUM_SEC" >> "$IPAM_ZONE_FILE";then 
    echo "Error: can not write zone file" 1>&2
    return 1
  fi
  echo "Created."
  echo "ZONE=\"$NAME\""
  printSoa
  unset DATA
  return 0
}

# @description ゾーンの削除
# @arg $1 削除するゾーン名
# @return 0 削除完了
# @return 1 削除不可
deleteZone(){
  if [[ $# -ne 1 ]];then
    echo "usage: ipam zone delete [name]"
    exit 1
  fi

  NAME="$1"

  if ! getZone;then
    echo "Zone Not Found... " 1>&2
    return 1
  fi

  echo "Target Found:"
  echo "  - Zone: \"$NAME\""
  echo "  - Description: \"$WHAT\""

  if ! askDelete;then
    return 1
  fi

  if ! sed -i "${HITLINENO}d" "${IPAM_ZONE_FILE}";then
    echo "Error: can not delete from zone file." 1>&2
    return 1
  fi
  echo "  Deleted \"$NAME\""
  unset HITLINENO
  return 0
}

editZone(){
  if [[ $# -ne 1 ]];then
    echo "usage: ipam zone edit [name]"
    exit 1
  fi
  NAME="$1"
  if ! getZone;then
    echo "Zone Not Found... " 1>&2
    return 1
  fi
  temp="$(mktemp)"
  getLineNumberOfZone;
cat << EOF > "$temp"
TTL="$TTL"
CONTACT="$CONTACT"
SERIAL="$SERIAL"
REFRESH_SEC="$REFRESH_SEC"
RETRY_SEC="$RETRY_SEC"
EXPIRE_SEC="$EXPIRE_SEC"
MINIMUM_SEC="$MINIMUM_SEC"
EOF

$EDITOR "$temp"
source "$temp"
rm -f "$temp"
newline="$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$NAME" "$WHAT" "$SERIAL" "$CONTACT" "$TTL" "$REFRESH_SEC" "$RETRY_SEC" "$EXPIRE_SEC" "$MINIMUM_SEC")"
oldline="$(sed -n "${HITLINENO}p" "$IPAM_ZONE_FILE")"
echo "@ CHECKING DIFF..."
if diff -up <(echo "$oldline") <(echo "$newline") ;then
  echo nodiff.
  return 1
fi
if ! sed -i "s/^$(echo "$NAME" | sed 's;\.;\.;g' )\t.*$/$newline/" "$IPAM_ZONE_FILE";then
  echo "Error: can not rewrite..." 1>&2
  return 1
fi
echo "* rewrited"
return 0


}
