#!/bin/bash

set -e
GEN_DATA_SCALE=$1
number_sessions=$2

if [[ "$GEN_DATA_SCALE" == "" || "$number_sessions" == "" ]]; then
	echo "Error: you must provide the scale and number of sessions as parameters."
	echo "Example: ./rollout.sh 3000 5"
	echo "This will execute the TPC-DS queries for 3TB of data and 5 concurrent sessions."
	exit 1
fi

PWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $PWD/../functions.sh
source_bashrc

get_file_count()
{
	count=$(ls $PWD/../log/end_testing* 2> /dev/null | wc -l)
}

rm -f $PWD/../log/*testing*.log
rm -f $PWD/query_*.sql

#create each session's directory
sql_dir=$PWD/$session_id
echo "sql_dir: $sql_dir"
for i in $(seq 1 $number_sessions); do
	sql_dir="$PWD"/"$session_id""$i"
	echo "checking for directory $sql_dir"
	if [ ! -d "$sql_dir" ]; then
		echo "mkdir $sql_dir"
		mkdir $sql_dir
	fi
	echo "rm -f $sql_dir/*.sql"
	rm -f $sql_dir/*.sql
done

#Create queries
echo "$PWD/dsqgen -streams $number_sessions -input $PWD/query_templates/templates.lst -directory $PWD/query_templates -dialect netezza -scale $GEN_DATA_SCALE -verbose y -output $PWD"
$PWD/dsqgen -streams $number_sessions -input $PWD/query_templates/templates.lst -directory $PWD/query_templates -dialect netezza -scale $GEN_DATA_SCALE -verbose y -output $PWD

#move the query_x.sql file to the correct session directory
for i in $(ls $PWD/query_*.sql); do
	stream_number=$(basename $i | awk -F '.' '{print $1}' | awk -F '_' '{print $2}')
	#going from base 0 to base 1
	stream_number=$((stream_number+1))
	echo "stream_number: $stream_number"
	sql_dir=$PWD/$stream_number
	echo "mv $i $sql_dir/"
	mv $i $sql_dir/
done
for x in $(seq 1 $number_sessions); do
	session_log=$PWD/../log/testing_session_$x.log
	echo "$PWD/test.sh $GEN_DATA_SCALE $x"
	$PWD/test.sh $GEN_DATA_SCALE $x > $session_log 2>&1 < $session_log &
done

get_file_count
echo "Now executing queries. This make take a while."
echo -ne "Executing queries."
while [ "$count" -lt "$number_sessions" ]; do
	echo -ne "."
	sleep 5
	get_file_count
done
echo "queries complete"
echo ""
$PWD/report.sh
