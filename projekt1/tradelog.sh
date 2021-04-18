#!/usr/bin/env bash
# Autor: Roman Klampar

POSIXLY_CORRECT=yes

CMD_LIST=( list-tick pos "profit" "last-price" "hist-ord" "graph-pos" )

declare -a ticker
declare -a fileName
declare -A lastP

cmd=""
xT=0


#	1			2		3				4			 5	   6   7
# DATUM a CAS;TICKER;TYP TRANSAKCIE;JEDNOTKOVA CENA;MENA;OBJEM;ID

USAGE=$(printf "usage:\n\t$0 [-h|--help] [FILTR] [PRIKAZ] [LOG [LOG2 [...]]]")

### Help Menu
function helpMenu() {
	echo "$USAGE"
	echo ""
	echo ". PRIKAZ:"
	printf "\tlist-tick\tvypis zoznamu vyskytujucich tickerov\n"
	printf "\tprofit\t\tvypis celkoveho zisku\n"
	printf "\tpos\t\tvypis aktualne drzanych pozic zoradenych podla hodnot\n"
	printf "\tlast-price\tvypis posledne zname ceny pre kazdy ticker\n"
	printf "\thist-ord\tvypis histogramu poctu transakcii podla tickerov\n"
	printf "\tgraph-pos\tvypis grau hodnot drzanych pozic podla tickerov\n"
	echo ". FILTR:"
	printf "\t-a DATETIME\tafter: uvazovane su LEN zaznamy PO tomto datume\n"
	printf "\t-b DATETIME\tbefore: uvazovane su LEN zaznamy PRED tymto datumom\n"
	printf "\t-t TICKER\tsu uvazovane zaznamy odpovedajuce danemu tickeru\n"
	printf "\t-w WIDTH\tu vypise grafu nastavuje dlzku najdlhsieho riadku\n"
	echo ""
	printf ". -h --help\tvypis help menu\n"
}

## MENU
while getopts ":a:b:t:w:h-:" opt; do
	case "$opt" in
		a) aDate="${OPTARG}" ;;
		b) bDate="${OPTARG}";;
		t) ticker[$xT]+=${OPTARG}; xT=$((xT+1));;
		w) width=${OPTARG}	;;
		h) helpMenu; exit 0;;			
		-) 
			case ${OPTARG} in
				"help") helpMenu; exit 0;;
				*) echo "$USAGE"; exit 1;;
			esac
	esac
done

((OPTIND--))
shift $OPTIND


# Kontroluje ci sa v argumente zadal PRIKAZ a LOGY

for f in "$@"; do
	if [ "$cmd" = "" ];then
		for c in "${CMD_LIST[@]}";do
			if [ "$c" = "$f" ]; then
				cmd="$f"; break
			fi
		done
	fi
	if [[ "$f" =~ ".log" ]] || [[ "$f" =~ ".log.gz" ]];then
		fileName+=("$f")
	fi
		
	shift	
done

########## Prikazy ##########

function getADate() {
	echo "$(echo "$1" | awk -F\; -v a="$aDate" 'a < $1 {print}')"
}

function getBDate() {
	echo "$(echo "$1" | awk -F\; -v b="$bDate" 'b > $1 {print}')"
}


#### FINALNE
## Funkcia filtruje na zaklade datumov
## $1 -> vsetky zaznamy z LOGOV
####

function checkDate() {
	t=""; tA=""; tB=""
	if [ -z "$aDate" ] && [ -z "$bDate" ];then
		t="$1"
	else
		if [ -z "$bDate" ];then
			t+="$(getADate "$1")"
		elif [ -z "$aDate" ];then
			t+="$(getBDate "$1")"
		else
			tA+="$(getADate "$1")"
			t+="$(getBDate "$tA")"
		fi
	fi	
	echo "$t"
}


#### FINAL
## Funkcia kontroluje zhodu dvoch slov
## $1 -> cely subor, z ktoreho hlada zhodu
## $2 -> pozadovane slovo, ktore hlada

function getTick() {
	echo "$(echo "$1" | awk -F\; -v x=$2 '$2 == x {print}')"
}


function checkTick() {
	t=""
	if [ "${#ticker[@]}" -eq 0 ];then
		t="$(checkDate "$1")"
	else
		for i in "${ticker[@]}";do
			s="$(getTick "$(checkDate "$1")" $i)"
			[[ -z "$t" ]] && t="$(printf "%s\n" "$s")" ||	
				t="$(printf "%s\n%s" "$t" "$s")"
		done
	fi
	echo "$(echo "$t" | sort -t\; -k1)"
}

#########################################
if [ "${#fileName[@]}" -eq 0 ];then
	stIn=""
	while read line;do
		if [ -z "$stIn" ];then
			stIn="$(printf "%s\n" "$line")"
		else
			stIn="$(printf "%s\n%s" "$stIn" "$line")"
		fi
	done < "${1:-/dev/stdin}"
fi


#### FINAL
# 
####

function parseFile() {
	total=""
	[[ ${#fileName[@]} -eq 0 ]] && total="$stIn" ||	
	for file in "${fileName[@]}";do
		if [[ "$file" =~ ".log.gz" ]];then
			s="$(gunzip -c "$file")"
		else
			s="$(cat "$file")"
		fi
		[[ -z "$total" ]] && total="$(printf "%s\n" "$s")" || 
			total="$(printf "%s\n%s" "$total" "$s")"
	done
	total="$(checkTick "$total")"
	echo "$total"
}

[[ -z "$cmd" ]] && echo "$(parseFile)"

function sortAndGetFirst() {
	echo "$(echo "$1" | awk -F\; -v t="$2" '$2 == t {print}' |sort -t\; -r -k1 | head -1)"
}


function sumProfit() {
	echo "$(echo "$1" | awk -F\; -v t="" '{if($3=="sell") 
												t+=($4*$6); 
											else t-=($4*$6);}
											END{printf "%.2f\n", t}')"
} 


function sumPos() {
	echo "$(echo "$1" | awk -F\; -v t=""  '{if ($3=="sell")
												t-=$6;
											else t+=$6;}
											END{printf "%.2f\n", t}')"
}


###### FINAL
# vypisuje zoznam tickerov v LOGOCH a zoraduje ich
#####

function funcListTick() {
	echo "$(parseFile | cut -d\; -f2 | sort -u)"
}



function funcProfit() {
	echo "$(sumProfit "$(parseFile)")"
}


function getLastPrice() {
	while read line;do
		p="$(echo "$(sortAndGetFirst "$(parseFile)" $line)" | cut -d\; -f4)"
		[[ -z "$p" ]] || lastP["$line"]=$p
	done <<< "$(funcListTick)"
}

function getMaxLen() {
	m=0	
	for i in "${!lastP[@]}";do
		[ ${#lastP[$i]} -gt $m ] && m=${#lastP[$i]}
	done
	echo $(($m+1))  	
}

function funcLastPrice() {
	getLastPrice
	m=$(getMaxLen)	
	for i in "${!lastP[@]}";do
		printf "%-10s|%$(($m))s\n" "$i" "${lastP[$i]}"
	done | sort
}

function setArrayPos() {
	getLastPrice

	for i in "${!lastP[@]}";do
		t="$(getTick "$(parseFile)" $i)"
		s="$(sumPos "$t")"
		su="$(awk -v a="$s" -v b="${lastP[$i]}" 'BEGIN {printf "%.2f", a*b}')"
		lastP[$i]="$su"
	done
}


function funcPos() {
	setArrayPos
	m=$(getMaxLen)
	for i in "${!lastP[@]}";do
		printf "%-10s:%$(($m))s\n" $i "${lastP[$i]}"
	done | sort -rn -k3
} 

##### FINAL
## funckia zobrazuje pocet zaznamov
## ak -w je nastave na velke cislo, nic sa nezobrazi...
## napr. AAPL ma 4zaznamy a -w 10 tak 4/10=0 cize ziadna #
#####

function funcHistOrd() {
	declare -A tic
	while read line;do
		n=$(echo "$(getTick "$(parseFile)" $line)" | wc -l)
		[[ -z "$width" ]] || n=$((n/width))
		[[ -z "$line" ]] || tic[$line]=$n
	done <<< "$(funcListTick)"

	for i in "${!tic[@]}";do
		y=${tic[$i]};d="#"
		s="$(awk -v d=$d -v x=$y 'BEGIN {OFS=d;$x=d;print}')"
		if [ $y -eq 0 ];then
			printf "%-10s:\n" $i
		else
			printf "%-10s: %s\n" $i $s
		fi
	done | sort	
}


function funcGraphPos() {
	setArrayPos
	[[ -z "$width" ]] && n=1000 || n=$((width*1000))
	while read line;do
		[[ -z "$line" ]] || nP=$(awk -v a=${lastP[$line]} -v b=$n 'BEGIN{printf "%d", a/b}')
		[[ -z "$line" ]] || lastP[$line]=$nP
	done <<< "$(funcListTick)"
	
	for i in "${!lastP[@]}";do
		y=${lastP[$i]}
		((y > 0)) && d="#" || d='!'
		((y > 0)) || y=$((y*-1))
		s="$(awk -v d=$d -v x=$y 'BEGIN {OFS=d;$x=d;print}')"
		((y == 0)) && printf "%-10s:\n" $i || printf "%-10s: %s\n" $i $s
	done | sort
}


# Na zaklade PRIKAZU vykonaj cinnost

case "$cmd" in
	"list-tick")  # TOTO BY MALO FUNGOVAT
			funcListTick;;
	"pos") # TOTO BY MALO TIEZ IST
			funcPos;;
	"profit") # TOTO BY MALO TIEZ FUNGOVAT
			funcProfit;;
	"last-price") # TOTO BY MALO TIEZ FUNGOVAT, ALE pomale pre .gz a format.
			funcLastPrice;;
	"hist-ord") # TOTO IDE TIEZ
			funcHistOrd;;
	"graph-pos") # TOTO TIEZ IDE 
			funcGraphPos;;
esac

