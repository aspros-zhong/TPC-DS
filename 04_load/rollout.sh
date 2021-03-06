#!/bin/bash
set -e

PWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $PWD/../functions.sh
source_bashrc

step=load
init_log $step

ADMIN_HOME=$(eval echo ~$ADMIN_USER)

copy_script()
{
	echo "copy the start and stop scripts to the hosts in the cluster"
	for i in $(cat $PWD/../segment_hosts.txt); do
		echo "scp start_gpfdist.sh stop_gpfdist.sh $ADMIN_USER@$i:$ADMIN_HOME/"
		scp $PWD/start_gpfdist.sh $PWD/stop_gpfdist.sh $ADMIN_USER@$i:$ADMIN_HOME/
	done
}

stop_gpfdist()
{
	echo "stop gpfdist on all ports"
	for i in $(cat $PWD/../segment_hosts.txt); do
		ssh -n -f $i "bash -c 'cd ~/; ./stop_gpfdist.sh'"
	done
}

start_gpfdist()
{
	stop_gpfdist
	sleep 1

	get_version
	if [[ "$VERSION" == "gpdb" || "$VERSION" == "hawq_1" ]]; then
		for i in $(psql -A -t -c "select rank() over (partition by hostname order by path), trim(hostname), trim(path) from data_dir order by hostname"); do
			CHILD=$(echo $i | awk -F '|' '{print $1}')
			EXT_HOST=$(echo $i | awk -F '|' '{print $2}')
			GEN_DATA_PATH=$(echo $i | awk -F '|' '{print $3}')
			GEN_DATA_PATH=$GEN_DATA_PATH/pivotalguru
			PORT=$(($GPFDIST_PORT + $CHILD))
			echo "executing on $EXT_HOST ./start_gpfdist.sh $PORT $GEN_DATA_PATH"
			ssh -n -f $EXT_HOST "bash -c 'cd ~/; ./start_gpfdist.sh $PORT $GEN_DATA_PATH'"
			sleep 1
		done
	else
		#HAWQ 2
		for i in $(psql -A -t -c "SELECT trim(path) || '/pivotalguru' FROM public.data_dir"); do
			GEN_DATA_PATH=$i
		done

		for i in $(cat $PWD/../segment_hosts.txt); do
			EXT_HOST=$i
			echo "executing on $EXT_HOST ./start_gpfdist.sh $GPFDIST_PORT $GEN_DATA_PATH"
			ssh -n -f $EXT_HOST "bash -c 'cd ~/; ./start_gpfdist.sh $GPFDIST_PORT $GEN_DATA_PATH'"
			sleep 1
		done
	fi
}

copy_script
start_gpfdist

for i in $(ls $PWD/*.sql); do
	start_log

	id=`echo $i | awk -F '.' '{print $1}'`
	schema_name=`echo $i | awk -F '.' '{print $2}'`
	table_name=`echo $i | awk -F '.' '{print $3}'`

	echo "psql -v ON_ERROR_STOP=1 -f $i | grep INSERT | awk -F ' ' '{print \$3}'"
	tuples=$(psql -v ON_ERROR_STOP=1 -f $i | grep INSERT | awk -F ' ' '{print $3}')

	log $tuples
done

stop_gpfdist

max_id=$(ls $PWD/*.sql | tail -1)
max_id=$(basename $max_id | awk -F '.' '{print $1}')

#might be able to remove this as Orca doesn't use the stats on partitions.  It only uses the root partition
#only analyze tables that need to be analyzed
for i in $(psql -A -t -v ON_ERROR_STOP=1 -c "SELECT lpad(row_number() over() + $max_id, 3, '0') || '.' || n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n on c.relnamespace = n.oid WHERE n.nspname = 'tpcds' AND c.relname NOT IN (SELECT DISTINCT tablename FROM pg_partitions p WHERE schemaname = 'tpcds') AND c.reltuples::bigint = 0"); do
	start_log

	id=`echo $i | awk -F '.' '{print $1}'`
	schema_name=`echo $i | awk -F '.' '{print $2}'`
	table_name=`echo $i | awk -F '.' '{print $3}'`

	echo "psql -a -v ON_ERROR_STOP=1 -c \"ANALYZE $schema_name.$table_name\""
	psql -a -v ON_ERROR_STOP=1 -c "ANALYZE $schema_name.$table_name"
	tuples="0"
	log $tuples
done

#only analyze root partitions that need to be analyzed
for i in $(psql -A -t -v ON_ERROR_STOP=1 -c "SELECT lpad(row_number() over() + $max_id, 3, '0') || '.' || n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n on c.relnamespace = n.oid WHERE n.nspname = 'tpcds' AND c.relname IN (SELECT DISTINCT tablename FROM pg_partitions p WHERE schemaname = 'tpcds') AND c.reltuples::bigint = 0"); do
	start_log

	id=`echo $i | awk -F '.' '{print $1}'`
	schema_name=`echo $i | awk -F '.' '{print $2}'`
	table_name=`echo $i | awk -F '.' '{print $3}'`

	echo "psql -a -v ON_ERROR_STOP=1 -c \"ANALYZE ROOTPARTITION $schema_name.$table_name\""
	psql -a -v ON_ERROR_STOP=1 -c "ANALYZE ROOTPARTITION $schema_name.$table_name"
	tuples="0"
	log $tuples
done

end_step $step
