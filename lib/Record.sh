#!/bin/bash -eu
# @file Record
# @brief 各ゾーンのレコード情報を管理するためのライブラリ
# @description 
source "$IPAM_SHELL_LIB/Utils.sh"

# /var/ipam-shell/zone.d/{ZONENAME}/{CustomRecord,ACache,PTRCache}
IPAM_ZONEINFO_BASEDIR="${IPAM_ZONEINFO_BASEDIR:-/var/ipam-shell/zone.d/}"
SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["ls"]="ListCustomRecord"
SUB_CMD_LIST["add"]="AddCustomRecord"
SUB_CMD_LIST["del"]="DeleteCustomRecord"

# @description Validate RDATA
validateRData(){
  DOMAIN_NAME=""; IPV4_ADDRESS=""; IPV6_ADDRESS="";
  case "$TYPE" in
    "A") # RFC 1035 3.4.1
      if grep -qP "$IPV4_ADDRESS" <<< "$RDATA";then
        return 0
      else
        return 1
      fi;;
    "AAAA") # RFC 3596
      if grep -qP "$IPV6_ADDRESS" <<< "$RDATA";then
        return 0
      else
        return 1
      fi;;
    "CNAME"|"NS") # RFC 1035 3.3.1, 3.3.11
      if grep -qP "$DOMAIN_NAME" <<< "$RDATA";then
        return 0
      else
        return 1
      fi;;
    "MX") # RFC 1035 3.3.9
      PREFERENCE="$(cut -d' ' -f1 <<< "$RDATA")"
      MAIL_EXCHANGE="$(cut -d' ' -f1 <<< "$RDATA")"
      if [[ $PREFERENCE -lt 0 ]] || [[ $PREFERENCE -gt 65535 ]];then
        # not 16 bit unsigned int
        return 1
      fi
      if grep -qP "$DOMAIN_NAME" <<< "$MAIL_EXCHANGE";then
        return 0
      else
        return 1
      fi;;
    "TXT")
      ;;
    "DS"|"RRSIG"|"DNSKEY"|"NSEC"|"NSEC3"|"TLSA")
      # DNSSEC/DANE
      return 0
      ;;
    "CAA")
      # Certificate, RFC 8659
      return 0
      ;;
    "SSHFP")
      # SSH Fingerprint  RFC 4205, RFC 6594(ECDSA/SHA256), RFC7479(Ed25519)
      ## 0: reserved, 1:RSA, 2:DSS, 3:ECDSA, 4:Ed25519
      #ALGORITHM="$(cut -d' ' -f1 <<< "$RDATA")"
      ## 0: reserved, 1:SHA-1, 2:SHA-256
      #FINGERPRINT_TYPE="$(cut -d' ' -f2 <<< "$RDATA")"
      #FINGERPRINT_VALUE="$(cut -d' ' -f3 <<< "$RDATA")"
      return 0
      ;;
    *)
      echo "Error: Unknown RR Type RR=\"$TYPE\"" 1>&2
      return 1
  esac
}
###################################################################
# @description カスタムレコードの一覧
ListCustomRecord(){
  set +u
  if [[ "$1" == "help" ]];then
    echo "usage: ipam record ls [zonename]"
    return 1
  fi
  set -u

  if [[ $# -ne 1 ]] ;then
    echo "* Can be limited by cmd: 'ipam record ls [zonename]'"
    while read -r path;do
      zonename="$(basename "$(dirname "$path")")"
      echo "** $zonename"
      cat <(echo -e "ID\tOWNER\tTYPE\tCLASS\tRDATA") <(nl -ba -s $'\t' "${path}") | column -ts $'\t'
      echo "---------------------"
    done < <(find "$IPAM_ZONEINFO_BASEDIR" -name CustomRecord -type f)

    return 0
  fi
  # OWNER, TYPE, CLASS, RDATA
  # e.g. www, A, IN, 192.0.2.1
  NAME="$1"
  cat <(echo -e "No.\tOWNER\tTYPE\tCLASS\tRDATA") <(nl -ba -s $'\t' "${IPAM_ZONEINFO_BASEDIR}/${NAME}/CustomRecord") | column -ts $'\t'
}

# @description レコードの追加
AddCustomRecord(){

  if [[ $# -ne 5 ]];then
    echo "usage: ipam record add [zonename] [owner] [type] IN [RDATA]"
    return 1
  fi

  ZONENAME="$1"
  OWNER="$2"
  TYPE="$3"
  CLASS="$4"
  RDATA="$5"

  source "$IPAM_SHELL_LIB/Zone.sh"
  if ! NAME="$ZONENAME" getZone;then
    echo "Error: Not Found a specific zone. Please check 'ipam zone ls'. zonename=\"$1\"" 1>&2
    exit 1
  fi

  BASEDIR="${IPAM_ZONEINFO_BASEDIR}/${ZONENAME}"
  mkdir -p "$BASEDIR"

  set +e
  FINDSTR="${OWNER}\t${TYPE}\t${CLASS}\t${RDATA}"
  FINDRES="$(grep -nxP "$FINDSTR" "$BASEDIR/CustomRecord")"
  set -e

  if [[ "$FINDRES" != "" ]];then
      HITLINENO="${FINDRES%%:*}"
    echo "Error: Same owner exist. ID=$HITLINENO" 1>&2
    exit 1
  fi


  if ! validateRData;then
    echo "Error: Unexptected Resource Data." 1>&2 
    exit 1
  fi
  if ! echo -e "${OWNER}\t${TYPE}\t${CLASS}\t${RDATA}" >> "${BASEDIR}/CustomRecord";then
    echo "Error: can not write to ${BASEDIR}/CustomRecord"
    exit 1
  fi

  echo "Added Record Owner=\"$OWNER\" Type=\"$TYPE\" RData=\"$RDATA\""
}

# @description レコードの削除
DeleteCustomRecord(){
  if [[ $# -ne 5 ]] && [[ "$2" != "id" ]];then
    echo "usage: ipam record del [zonename] [owner] [type] IN [RDATA]"
    echo "usage: ipam record del [zonename] id [id]"
    return 1
  fi
  source "$IPAM_SHELL_LIB/Zone.sh"

  ZONENAME="$1"
  if ! NAME="$ZONENAME" getZone;then
    echo "Error: Not Found a specific zone. Please check 'ipam zone ls'. zonename=\"$1\"" 1>&2
    exit 1
  fi
 
  CustomRecord="${IPAM_ZONEINFO_BASEDIR}/${ZONENAME}/CustomRecord"

  if [[ "$2" == "id" ]];then
    HITLINENO="$3"
    set +e
    RESULT="$(sed -n "${HITLINENO}p" "$CustomRecord" )"
    set -e
    if [[ "$RESULT" == "" ]];then
      echo "Error: Record Not Found." 1>&2
      exit 1
    fi
    echo "Target:"
    echo "$RESULT"
    if ! askDelete;then
      echo "nothing."
      exit 1
    fi

  else

    OWNER="$2"
    TYPE="$3"
    CLASS="$4"
    RDATA="$5"

    if ! [[ -f "$CustomRecord" ]];then
      echo "Error: Not Created Records not even once... \"$CustomRecord\" not found." 1>&2
      exit 1
    fi

    set +e
    FINDSTR="${OWNER}\t${TYPE}\t${CLASS}\t${RDATA}"
    FINDRES="$(grep -nxP "$FINDSTR" "$CustomRecord")"
    set -e

    if [[ "$FINDRES" == "" ]];then
      echo "Error: Record not found." 1>&2
      exit 1
    fi
    HITLINENO="${FINDRES%%:*}"
  fi

  if ! sed -i "${HITLINENO}d" "$CustomRecord";then
    echo "Error: can not delete from zone file." 1>&2
    return 1
  fi
  echo "Deleted. (LINE=$HITLINENO)"
  return 0
}

