#!/bin/bash
set -e

PWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $PWD/../functions.sh
source_bashrc

for i in $(ls $PWD/*.sql | grep -v report.sql); do
        schema_name=`echo $i | awk -F '.' '{print $2}'`
	EXECUTE="'cat $PWD/../log/rollout_$schema_name*.log'"
        echo "psql -v ON_ERROR_STOP=1 -a -f $i -v EXECUTE=\"$EXECUTE\""
        psql -v ON_ERROR_STOP=1 -a -f $i -v EXECUTE="$EXECUTE"
        echo ""
done

psql -v ON_ERROR_STOP=1 -P pager=off -f $PWD/detailed_report.sql
echo ""
psql -v ON_ERROR_STOP=1 -P pager=off -f $PWD/summary_report.sql
