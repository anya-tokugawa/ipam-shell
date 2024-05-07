#!/bin/bash
# @file Utils
# @brief 各種I/Oとか対話とかのユーティリティ
# @description 


askDelete(){
  echo -n "Do you really want to delete it?(y/n): "
  read -r ok
  
  if [[ "$ok" != "y" ]];then
    unset HITLINENO
    echo "> holded."
    return 1
  fi
  return 0
}

# @description エントリ行の削除
# @arg $1 行番号
# @arg $2 対象ファイル
deleteLine(){
  if sed -i "${1}d" "${2}";then
    echo "* Successfly deleted entry."
    return 0
  else
    echo "* Failed to delete entry" 1>&1
    return 1
  fi
}

# IPアドレス表記 -> 32bit値 に変換
ip2decimal(){
    local IFS=.
    local c=($1)
    printf "%s\n" $(( (${c[0]} << 24) | (${c[1]} << 16) | (${c[2]} << 8) | ${c[3]} ))
}

# 32bit値 -> IPアドレス表記 に変換
decimal2ip(){
    local n=$1
    printf "%d.%d.%d.%d\n" "$((n >> 24))" "$(( (n >> 16) & 0xFF))" "$(( (n >> 8) & 0xFF))" "$((n & 0xFF))"
}

# CIDR 表記のネットワークアドレスを 32bit値に変換
prefix2numof(){
    # /24 --> 255
    printf "%s\n" "$(( 2 ** (32-$1)-1 ))"
}


cidr2hostlist(){
    local num max
		num=$(( 1 + $(ip2decimal "$(echo "$1" | cut -d'/' -f1)") ))
		max=$(( num + $(prefix2numof "$(echo "$1" | cut -d'/' -f2)") - 1))
    while [[ "$num" -lt "$max" ]];do
        decimal2ip "$num"
        num=$((num+1))
    done
}
