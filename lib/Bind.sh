source "$IPAM_SHELL_LIB/Utils.sh"
source "$IPAM_SHELL_LIB/Record.sh"
source "$IPAM_SHELL_LIB/Zone.sh"
source "$IPAM_SHELL_LIB/Segment.sh"
source "$IPAM_SHELL_LIB/Ipam.sh"
unset SUB_CMD_LIST
declare -A SUB_CMD_LIST


SUB_CMD_TYPE="FUNC"
SUB_CMD_LIST["gen-zone"]="GenerateZoneConfig"
SUB_CMD_LIST["gen-inc"]="GenerateIncludeConfig"

GenerateZoneConfig(){
  if [[ $# -ne 1 ]];then
    echo "usage: ipam bind gen-zone [prefix-dir]"
    exit 1
  fi
  source "$IPAM_SHELL_LIB/Segment.sh"
  t1="$(mktemp)"
  t2="$(mktemp)"
  echo "mkdir -p \"${1}\""
  echo ""
  while read -r zonename;do
    echo "cat << 'END_OF_ZONE_CONFIG' > \"${1}/${zonename}zone\""
    NAME="$zonename"
    printSoa
    echo "; CustomRecord"
    if [[ -f "${IPAM_ZONEINFO_BASEDIR}/${NAME}/CustomRecord" ]];then
      column -ts$'\t'  "${IPAM_ZONEINFO_BASEDIR}/${NAME}/CustomRecord"
    fi
    echo "; Hosts"
    # lookup cidr.
    if ! getCidrByDomain;then
      #echo "; Warning: Not Found Connect Domain" 1>&2
      echo "END_OF_ZONE_CONFIG"
      echo ""
      continue
    fi
    # cidr to ipaddress file to and grep, ip addreess and host assign here.
    cidr2hostlist "$HITCIDR" |  sed -e 's;^;\t;g' -e 's;$;\t;g' > "$t1"
    # cut of ip address and 
    set +e
    grep -Ff "$t1" "$IPAM_IPADDRESS_FILE" > "$t2"
    set -e
    while IFS=$'\t' read -r UUID IP_ADDRESS DNS_HOSTNAME ENABLE_REV_RECORD;do
      echo -e "${DNS_HOSTNAME}\tIN\tA\t${IP_ADDRESS}"
    done < "$t2" | column -ts $'\t'
    echo "END_OF_ZONE_CONFIG"
    echo ""

  done < <(listZoneName)
  rm -f "$t1" "$t2"




}
GenerateIncludeConfig(){
  if [[ $# -ne 1 ]];then
    echo "usage: ipam bind gen-inc [prefix-dir]"
    exit 1
  fi
  source "$IPAM_SHELL_LIB/Segment.sh"
  while read -r zonename;do
    echo -e "zone \"${zonename}\"\t{ type master; file \"${1}/${zonename}zone\"; };"
  done < <(listZoneName) | column -ts $'\t'
}
