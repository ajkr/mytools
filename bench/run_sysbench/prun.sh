# max value for --num-threads
maxdop=$1

# base directory for mysql install
ibase=$2

# if yes then run mysql as root else ignore
runasroot=$3

# user, password and database to use
myu=$4
myp=$5
myd=$6

# name of storage engine
engine=$7

# number of rows
nr=$8

# Test duration
t=${9}

# rw : (default, no extra params)
# ro   : --oltp-read-only --oltp-skip-trx
# si   : --oltp-read-only --oltp-skip-trx --oltp-test-mode=simple
# roha : --oltp-read-only --oltp-skip-trx --oltp-point-select-mysql-handler
# siha : --oltp-read-only --oltp-skip-trx ---oltp-point-select-mysql-handler --oltp-test-mode=simple
# sihaorc : --oltp-read-only --oltp-skip-trx ---oltp-point-select-mysql-handler-open-read-close --oltp-test-mode=simple
# siac : --oltp-read-only --oltp-skip-trx --oltp-test-mode=simple --oltp-point-select-all-cols
# sij : --oltp-read-only --oltp-skip-trx --oltp-test-mode=simplejoin 
# incupd : --oltp-skip-trx --oltp-test-mode=incupdate
# incupd2 : --oltp-skip-trx --oltp-test-mode=incupdate2
# updnokey : --oltp-test-mode=nontrx --oltp-nontrx-mode=update_nokey
# incins : --oltp-skip-trx --oltp-test-mode=incinsert
# sirw : --oltp-skip-trx --oltp-test-mode=simple --oltp-point-select-all-cols --oltp-simple-update
# siro : --oltp-read-only --oltp-point-selects=0 --oltp-simple-ranges=0 --oltp-order-ranges=0 --oltp-distinct-ranges=0 --oltp-sum-ranges=1
# sirolist : --oltp-read-only --oltp-point-selects=0 --oltp-simple-ranges=0 --oltp-order-ranges=0 --oltp-distinct-ranges=0 --oltp-sum-ranges=0 --oltp-inlist-values=1
# range : 1 range query per trx

strx=${10}

# if yes then prepare the sbtest table else ignore
prepare=${11}

# if yes then drop the sbtest table at test end else ignore
drop=${12}

# --mysql-engine-trx=[yes,no]
etrx=${13}

dbh=${14}

# when 'no' --oltp-secondary
usepk=${15}

# distribution u==uniform, s==special
dist=${16}

# yes -> warmup the buffer cache
warmup=${17}

# value for --oltp-range-size
range=${18}

nclients=${19}

use_compress=${20}

restart=${21}

shift 21

echo use $nclients clients and $nr rows and $t secs and host $dbh

while (( "$#" )) ; do
  b=$1
  echo use binary $b
  shift 1
  mybase=$ibase/$b
  mysock=$mybase/var/mysql.sock
  echo Running $b from $mybase

  ssh root@$dbh "ps aux | grep mstat\.py | grep -v grep | awk '{ print \$2 }' | xargs kill -9"

  mysql=$mybase/bin/mysql
  run_mysql="$mysql -u$myu -p$myp -h$dbh -A "

  if [[ $restart = "yes" ]]; then
    echo Run ssh root@$dbh "$mybase/bin/mysqladmin -u$myu -p$myp -S$mysock shutdown"
    ssh root@$dbh "$mybase/bin/mysqladmin -u$myu -p$myp -S$mysock shutdown"

    if [[ $runasroot == "yes" ]] ; then
      echo ssh root@$dbh "cd $mybase; bin/mysqld_safe --user=root > /dev/null 2>&1 &"
      ssh root@$dbh "cd $mybase; bin/mysqld_safe --user=root > /tmp/so 2>&1 &"
    else
      echo ssh start
      ssh root@$dbh "$mybase/bin/mysqld_safe > /dev/null 2>&1 &"
    fi
    sleep 1 
    ssh root@$dbh "ls -l $mysock"
    echo Sleep after startup  
    sleep 40

  fi

  echo ssh root@$dbh "$mybase/bin/mysql -u$myu -p$myp -S$mysock -e \"grant all on *.* to root@'%' identified by '$myp' \" "
  ssh root@$dbh "$mybase/bin/mysql -u$myu -p$myp -S$mysock -e \"grant all on *.* to root@'%' identified by '$myp' \" "
  ssh root@$dbh "$mybase/bin/mysql -u$myu -p$myp -S$mysock mysql -e \"delete from user where length(Password) = 0; flush privileges;\""

  rm -f ready.* go.*

  for c in $( seq 1 $nclients ); do
    echo Running $b $engine for client $c of $nclients
    rm -f startme.$c
    echo bash prun1.sh $engine $t $nr $strx $etrx $mysql $maxdop $prepare $myu $myp $myd $dbh $usepk $dist $warmup $range $c $nclients $mybase $use_compress
    bash prun1.sh $engine $t $nr $strx $etrx $mysql $maxdop $prepare $myu $myp $myd $dbh $usepk $dist $warmup $range $c $nclients $mybase $use_compress > \
        sb.$c.o.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist &
    fid[${c}]=$!
    echo client $c has pid ${fid[${c}]}
  done

  for c in $( seq 1 $nclients ); do
    while [[ ! -f startme.$c ]]; do echo "wait for startme.$c"; sleep 5; done
  done

  rm -f startme.*

  # for i in $( seq 0 18 ) ; do $mybase/bin/mysql -u$myu -p$myp -h$dbh -e "show engine innodb status\G"; sleep 60 ; done > \
  #      sb.sis.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist &

  ssh root@$dbh killall vmstat
  ssh root@$dbh "vmstat 10 100000" > sb.v.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist &

  ssh root@$dbh killall iostat
  ssh root@$dbh "iostat -x 10 100000" > sb.i.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist &

  ssh root@$dbh "ps aux | grep mstat\.py | grep -v grep | awk '{ print \$2 }' | xargs kill -9"
  ssh root@$dbh "python ${mybase}/mstat.py --loops 1000000 --interval 10 --db_user=$myu --db_password=$myp --db_host=$dbh" \
                 > sb.mstat.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist &
 
  for c in $( seq 1 $nclients ); do
    echo wait for client $c with pid ${fid[${c}]}
    ps aux | grep ${fid[${c}]} | grep -v grep
    wait ${fid[${c}]}
  done
  echo Done waiting

  rm -f /tmp/pres; touch /tmp/pres
  echo -n $b "$engine " > sb.r.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  for c in $( seq 1 $nclients ); do
    grep transactions: sb.$c.o.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | awk '{ print $4 }' | tr '(' ' ' | awk '{ printf "%s \n", $1 }' > /tmp/res.$c
    paste /tmp/pres /tmp/res.$c > /tmp/pres.2; mv /tmp/pres.2 /tmp/pres
  done
  awk '{ s=0; for (i=1; i <= NF; i += 1) { s += $i }; printf "%s ", s }' /tmp/pres >> sb.r.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  echo >> sb.r.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  rm -f /tmp/pres; touch /tmp/pres
  echo -n $b "$engine " > sb.avg.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  for c in $( seq 1 $nclients ); do
    grep avg: sb.$c.o.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | grep -v percent | awk '{ print $3 }' | tr 'ms' ' ' | awk '{ printf "%s \n", $1 }' > /tmp/res.$c
    paste /tmp/pres /tmp/res.$c > /tmp/pres.2; mv /tmp/pres.2 /tmp/pres
  done
  awk '{ x=0; for (i=1; i <= NF; i += 1) { if ($1 > x) { x = $1 } }; printf "%s ", x }' /tmp/pres >> sb.avg.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  echo >> sb.avg.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  rm -f /tmp/pres; touch /tmp/pres
  echo -n $b "$engine " > sb.p99.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  for c in $( seq 1 $nclients ); do
    grep percentile: sb.$c.o.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | grep approx | awk '{ print $5 }' | tr 'ms' ' ' | awk '{ printf "%s \n", $1 }' > /tmp/res.$c
    paste /tmp/pres /tmp/res.$c > /tmp/pres.2; mv /tmp/pres.2 /tmp/pres
  done
  awk '{ x=0; for (i=1; i <= NF; i += 1) { if ($1 > x) { x = $1 } }; printf "%s ", x }' /tmp/pres >> sb.p99.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  echo >> sb.p99.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  ssh root@$dbh killall vmstat
  ssh root@$dbh killall iostat
  ssh root@$dbh "ps aux | grep mstat\.py | grep -v grep | awk '{ print \$2 }' | xargs kill -9"

  #
  # Innodb mutex stats
  #
  echo Get stats
  $run_mysql -B -e 'show engine innodb mutex' > sb.ms.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  cat sb.ms.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | \
    grep -v Status | \
    tr '=' ' ' | \
    awk '{ printf "%10d\t%s\n", $4, $2 }' | \
    sort -rnk 2 > \
    sb.msn.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist 

  # By mutex
  sort -k 2,2 sb.msn.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | \
    awk '{ if ($2 != pk) { if (s > 0) { printf "%10d\t%s\n", s, pk }; s = $1; pk = $2 } else { s += $1 } } END { if (s > 0) { printf "%10d\t%s\n", s, pk } } ' | \
    sort -r -n -k 1,1 | \
    head -50 > sb.msa.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  # By callers
  # sort -k 1,1 sb.ms.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | \
  #  awk '{ if ($1 != pk) { if (s < 0) { printf "%10d\t%s\n", -s, pk }; s = $2; pk = $1 } else { s += $2 } } END { if (s < 0) { printf "%10d\t%s\n", -s, pk } } '  | \
  #  sort -r -n -k 1,1 | \
  #  head -20 > sb.cms20.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  #
  # General mutex stats
  #
  echo Get global mutex stats
  $run_mysql -e 'show engine innodb mutex' > sb.gs.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  # By mutex
  # $run_mysql -B -e 'show global mutex status' | head -1 > sb.gs20.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  # sort -r -n -k 3,3 sb.gs.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist | grep -v Sleeps | head -20 > sb.gs20.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  $run_mysql -e 'select * from information_schema.user_statistics\G' > sb.us.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  $run_mysql -e 'select * from information_schema.table_statistics\G' > sb.ts.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  $run_mysql -e 'show engine innodb status\G' > sb.esi.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist
  $run_mysql -e 'show engine rocksdb status\G' > sb.esi.$engine.$b.t_$t.r_$nr.tx_$strx.pk_$usepk.dist_$dist

  if [[ $drop != "no" ]]; then
    echo Drop tables
    for c in $( seq 1 $nclients ); do
      $run_mysql $myd -e "drop table sbtest${id}"
    done
  fi

  if [[ $restart = "yes" ]]; then
    echo Running $b shutdown at $( date )
    ssh root@$dbh "ls -l $mysock"
    ssh root@$dbh "$mybase/bin/mysqladmin -u$myu -p$myp -S$mysock shutdown"
    echo Shutdown done
    sleep 5
  fi

  echo Sleep done
done

echo Goodbye
