#!/bin/bash

# Try to guess TESTDIR if it is not set
[ -z $TESTDIR ] && export TESTDIR=/loadgentests

# Check that we have some needed tools
checkfor() {
  which $1 >/dev/null
  if [ $? -ne 0 ]; then
    echo "Error: failed to find \"${1}\" (PATH=$PATH)"
    exit 1
  fi
}
checkfor which
checkfor cp
checkfor mv
checkfor rm
checkfor bc
checkfor tee
checkfor awk
checkfor sed
checkfor cut
checkfor grep
checkfor expr
checkfor echo
checkfor tail
checkfor egrep
checkfor mkdir
checkfor column

export TARGETURL=""
export CONCURRENT=20
export REQUESTS=1000
export DURATION=10

# replace fname str replace-str
replace() {
  FNAME=$1
  STR=$2
  REPLACE=$3
  awk -v rep="${REPLACE}" '{gsub("'${STR}'", rep);print $0}' ${FNAME} >/tmp/_replace.tmp
  mv -f /tmp/_replace.tmp ${FNAME}
}

# replace_all $source_cfg $target_cfg
replace_all() {
  SRC=$1
  DEST=$2
  cp -f $SRC $DEST
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  TARGETHOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  TARGETPATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
  RATE=`expr ${REQUESTS} \/ ${DURATION}`
  replace $DEST "REQS_PER_VU" "${REQS_PER_VU}"
  replace $DEST "CONCURRENT" "${CONCURRENT}"
  replace $DEST "DURATION" "${DURATION}"
  replace $DEST "RATE" "${RATE}"
  replace $DEST "TARGETHOST" "${TARGETHOST}"
  replace $DEST "TARGETPATH" "${TARGETPATH}"
  replace $DEST "TARGETURL" "${TARGETURL}"
  replace $DEST "LOGDIR" "${RESULTS}"
}

# utility func to interpret "Xs", "Xms", "Xus", "Xns" durations and translate them to ms
duration2ms() {
  read X
  UNIT=`echo $X |egrep -o '[mun]?s'`
  NUM=`echo $X |sed 's/'${UNIT}'//'`
  if [ "${UNIT}x" = "sx" ]; then
    echo "${NUM}*1000" |bc
  elif [ "${UNIT}x" = "usx" ]; then
    echo "scale=2; x=${NUM}/1000; if (x<1) print 0; x" |bc
  elif [ "${UNIT}x" = "nsx" ]; then
    echo "scale=2; x=${NUM}/1000000; if (x<1) print 0; x" |bc
  elif [ "${UNIT}x" = "msx" ]; then
    echo ${NUM}
  else
    echo "error: unknown unit in duration: ${1}"
  fi
}

# 1 param: filename containing test data from one or more tests, in this format:
# TESTNAME, REQUESTS, ERRORS, RPS, RTTMIN, RTTMAX, RTTAVG(mean), RTTp50(median), RTTp75, RTTp90, RTTp95, RTTp99
# Use "-" if there is no result for that param
# optional 2nd param is a header to also be sent to column
report() {
  ( if [ $# -gt 1 ]; then
      echo "$2"
    fi
    awk '{printf $1" "; \
      if ($2=="-" || $2==0)printf "- "; else printf "requests="$2" "; \
      if ($3=="-" || $3==0)printf "- "; else printf "errors="$3" "; \
      if ($4=="-" || $4==0)printf "- "; else printf "rps="$4" "; \
      if ($5=="-" || $5==0)printf "- "; else printf "rttmin="$5" "; \
      if ($6=="-" || $6==0)printf "- "; else printf "rttmax="$6" "; \
      if ($7=="-" || $7==0)printf "- "; else printf "rttavg="$7" "; \
      if ($8=="-" || $8==0)printf "- "; else printf "rtt50="$8" "; \
      if ($9=="-" || $9==0)printf "- "; else printf "rtt75="$9" "; \
      if ($10=="-" || $10==0)printf "- "; else printf "rtt90="$10" "; \
      if ($11=="-" || $11==0)printf "- "; else printf "rtt95="$11" "; \
      if ($12=="-" || $12==0)print "-"; else print "rtt99="$12}' $1 ) |column -t
}

# Take a decimal or integer number and strip it to at most 2-digit precision
stripdecimals() {
  read X
  echo $X |egrep -o '^[0-9]*\.?[0-9]?[0-9]?'
}

# Static-URL tests
apachebench_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  PERCENTAGES=${RESULTS}/percentages
  echo "${TESTNAME}: Executing ab -k -e ${PERCENTAGES} -t ${CONCURRENT} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  ab -k -e ${PERCENTAGES} -t ${CONCURRENT} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _REQUESTS=`grep '^Complete\ requests:' ${RESULTS}/stdout.log |awk '{print $3}'`
  _RPS=`grep '^Requests\ per\ second:' ${RESULTS}/stdout.log |awk '{print $4}' |stripdecimals`
  _RTTAVG=`grep '^Time\ per\ request:' ${RESULTS}/stdout.log |grep '(mean)' |awk '{print $4}' |stripdecimals`
  _ERRORS=`grep '^Failed\ requests:' ${RESULTS}/stdout.log |awk '{print $3}'`
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50=`grep '^50,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}'`
  _RTTp75=`grep '^75,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}'`
  _RTTp90=`grep '^90,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}'`
  _RTTp95=`grep '^95,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}'`
  _RTTp99=`grep '^99,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}'`
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

wrk_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  # Note that we supply TARGETURL on the cmd line as wrk requires that, but the cmd line parameter will
  # not be used as our script decides what URL to load (which will of course be the same TARGETURL though)
  echo "${TESTNAME}: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _RPS=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep '^Requests/sec:' |awk '{print $2}' |stripdecimals`
  _RTTAVG=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |duration2ms |stripdecimals`
  _REQUESTS=`grep ' requests in ' ${RESULTS}/stdout.log |tail -1 |awk '{print $1}'`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX=`grep -A 2 'Thread stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $4}' |duration2ms |stripdecimals`
  _RTTp50=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="50%"{print $2}' |duration2ms |stripdecimals`
  _RTTp75=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="75%"{print $2}' |duration2ms |stripdecimals`
  _RTTp90=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="90%"{print $2}' |duration2ms |stripdecimals`
  _RTTp95="-"
  _RTTp99=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="99%"{print $2}' |duration2ms |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

boom_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  echo "${TESTNAME}: Executing boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _RPS=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Requests/sec:' |awk '{print $2}' |stripdecimals`
  _DURATION=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Total:' |awk '{print $2}'`
  _REQUESTS=`grep ' \[200\] ' ${RESULTS}/stdout.log |grep ' responses' |awk '{print $2}'`
  _ERRORS=`grep -A 10 '^Status code distribution:' ${RESULTS}/stdout.log |grep -v ' \[200\] ' |grep ' responses' |awk 'BEGIN{tot=0}{tot=tot+$2}END{print tot}'`
  _RTTMIN=`egrep 'Fastest: [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTMAX=`egrep 'Slowest: [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTAVG=`egrep 'Average: [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTp50=`egrep '50% in [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp75=`egrep '75% in [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp90=`egrep '90% in [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp95=`egrep '95% in [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp99=`egrep '99% in [0-9]*\.?[0-9]* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

artillery_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  echo "${TESTNAME}: Executing artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} -o ${RESULTS}/artillery_report.json ${TARGETURL} ... "
  _START=`date +%s.%N`
  artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} -o ${RESULTS}/artillery_report.json ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`date +%s.%N`
  _DURATION=`echo "${_END}-${_START}" |bc`
  _REQUESTS=`grep -A 20 '^Complete report @' ${RESULTS}/stdout.log |grep 'Requests completed:' |awk '{print $3}'`
  _RPS=`grep -A 20 '^Complete report @' ${RESULTS}/stdout.log |grep 'RPS sent:' |awk '{print $3}' |stripdecimals`
  #export ARTILLERY_RTTMED=`grep -A 20 '^Complete report @' stdout.log |grep -A 5 'Request latency:' |grep "median:" |awk '{print $2}'`
  # Artillery only reports median RTT, so we attempt to calculate the average here
  # TODO: Use the artillery_report.json logfile that contains individual transaction times, to calculate average RTT
  _RTTAVG=`echo "scale=2; x=1000/((${_REQUESTS}/${CONCURRENT})/${_DURATION}); if (x<1) print 0; x" |bc |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}
vegeta_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  # Vegeta only supports static request rates. You might want to change the REQUESTS parameter until you get the highest throughput w/o errors.
  _RATE=`expr ${REQUESTS} \/ ${DURATION}`
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  echo "${TESTNAME}: Executing echo \"GET ${TARGETURL}\" vegeta attack -rate=${_RATE} -connections=${CONCURRENT} -duration=${DURATION}s ... "
  echo "GET ${TARGETURL}" |vegeta attack -rate=${_RATE} -connections=${CONCURRENT} -duration=${DURATION}s |vegeta report > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _REQUESTS=`grep '^Requests' ${RESULTS}/stdout.log |awk '{print $4}' |cut -d\, -f1 |awk '{print $1}'`
  _RPS=`grep '^Requests' ${RESULTS}/stdout.log |awk '{print $5}' |stripdecimals`
  _RTTAVG=`grep '^Latencies' ${RESULTS}/stdout.log |awk '{print $7}' |egrep -o '[0-9]*\.?[0-9]*' |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

siege_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  echo "${TESTNAME}: Executing siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} ... "
  siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  # Doesnt seem possible to tell siege where to write its logfile
  mv -f /var/log/siege.log ${RESULTS}
  _REQUESTS=`grep '^Transactions:' ${RESULTS}/stderr.log |awk '{print $2}'`
  _RPS=`grep '^Transaction rate:' ${RESULTS}/stderr.log |awk '{print $3}' |stripdecimals`
  _RTT_SECS=`grep '^Response time:' ${RESULTS}/stderr.log |awk '{print $3}'`
  # Siege reports response time in seconds, with only 2 decimals of precision. In a benchmark it is not unlikely
  # you will see it report 0.00s response times, or response times that never change. Given this lack of precision 
  # it may perhaps be better to calculate average response time, like we do for Artillery?
  _RTTAVG=`echo "${_RTT_SECS}*1000" |bc |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

tsung_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/tsung_${STARTTIME}.xml
  replace_all ${TESTDIR}/configs/tsung.xml ${CFG}
  echo "${TESTNAME}: Executing tsung -l ${RESULTS} -f ${CFG} start ... "
  _START=`date +%s.%N`
  tsung -l ${RESULTS} -f ${CFG} start > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`date +%s.%N`
  _DURATION=`echo "${_END}-${_START}" |bc`
  _LOGDIR=`grep '^Log directory is:' ${RESULTS}/stdout.log |awk '{print $4}'`
  _RTTAVG=`grep '^stats: request ' ${_LOGDIR}/tsung.log |tail -1 |awk '{print $8}' |stripdecimals`
  if [ "${_RTTAVG}x" = "0x" ]; then
    _RTTAVG=`grep '^stats: request ' ${_LOGDIR}/tsung.log |tail -1 |awk '{print $4}' |stripdecimals`
    _REQUESTS=`grep '^stats: request ' ${_LOGDIR}/tsung.log |tail -1 |awk '{print $3}'`
  else
    _REQUESTS=`grep '^stats: request ' ${_LOGDIR}/tsung.log |tail -1 |awk '{print $9}'`
  fi
  _RPS=`echo "scale=2; x=${_REQUESTS}/${_DURATION}; if (x<1) print 0; x" |bc |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}
jmeter_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/jmeter_${STARTTIME}.xml
  # TODO: support for protocols other than plain HTTP... we dont specify protocol in the test plan ATM
  replace_all ${TESTDIR}/configs/jmeter.xml ${CFG}
  echo "${TESTNAME}: Executing jmeter -n -t ${CFG} ... "
  ${TESTDIR}/apache-jmeter-3.0/bin/jmeter -n -t ${CFG} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _REQUESTS=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $3}'`
  _RPS=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $7}' |cut -d\/ -f1 |stripdecimals`
  _RTTAVG=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $9}' |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

# Scripting tests
locust_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/locust_${STARTTIME}.py
  # TODO: we only support plain HTTP here also
  replace_all ${TESTDIR}/configs/locust.py ${CFG}
  _TARGETHOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  _START=`date +%s.%N`
  echo "${TESTNAME}: Executing locust --host=\"http://${_TARGETHOST}\" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} ... "
  locust --host="http://${_TARGETHOST}" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`date +%s.%N`
  _REQUESTS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Total' |awk '{print $2}'`
  # Locust RPS reporting is not reliable for short test durations (it can report 0 RPS)
  _RPS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Total' |awk '{print $4}' |stripdecimals`
  if [ "${_RPS}x" = "0.00x" ]; then
    # Calculate some average RPS instead
    _DURATION=`echo "${_END}-${_START}" |bc`
    _RPS=`echo "scale=2; x=${_REQUESTS}/${_DURATION}; if (x<1) print 0; x" |bc |stripdecimals`
  fi
  _RTTAVG=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ GET' |head -1 |awk '{print $5}' |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

grinder_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/grinder_${STARTTIME}.py
  replace_all ${TESTDIR}/configs/grinder.py ${CFG}
  CFG2=${TESTDIR}/configs/grinder_${STARTTIME}.properties
  TMPCFG2=/tmp/grinder_${STARTTIME}.properties
  cp ${TESTDIR}/configs/grinder.properties $TMPCFG2
  # Grinder specifies thread duration in ms
  _DURATION=`expr ${DURATION} \* 1000`
  replace $TMPCFG2 "DURATION" "${_DURATION}"
  replace $TMPCFG2 "SCRIPT" "${CFG}"
  replace_all $TMPCFG2 $CFG2
  rm $TMPCFG2
  cd ${TESTDIR}/configs
  export CLASSPATH=/loadgentests/grinder-3.11/lib/grinder.jar
  echo "${TESTNAME}: Executing java net.grinder.Grinder ${CFG2} ... "
  java net.grinder.Grinder ${CFG2} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  # Grinder only logs durations for individual requests. I don't think there is any simple way of making it
  # output aggregated statistics to the console, so we have to first find out what our workers are called
  TMP=${RESULTS}/_metrics.`date +%s`
  for WORKER in `egrep 'INFO  agent: worker .* started' ${RESULTS}/stdout.log |awk '{print $6}'`
  do
    # Then we extract all the response time metrics from the logfiles
    awk 'NR>1{print $5}' ${RESULTS}/${WORKER}-data.log |sed 's/\,//' >>${TMP}
  done
  # How many requests did we see
  _REQUESTS=`wc -l ${TMP} |awk '{print $1}'`
  # Calculate RPS. We assume we ran for the exact DURATION.
  _RPS=`echo "scale=2; x=${_REQUESTS}/${DURATION}; if (x<1) print 0; x" |bc |stripdecimals`
  # Calculate the average for all the response times. 
  _RTTAVG=`awk 'BEGIN{num=0;tot=0}{num=num+1;tot=tot+$1}END{print tot/num}' ${TMP} |stripdecimals`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX="-"
  _RTTp50="-"
  _RTTp75="-"
  _RTTp90="-"
  _RTTp95="-"
  _RTTp99="-"
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}
gatling_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/gatling_${STARTTIME}.scala  
  replace_all ${TESTDIR}/configs/gatling.scala ${CFG}
  echo "${TESTNAME}: Executing gatling ... "
  # TODO - fix Gatlings tricky config setup...  
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}
wrk_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS="${RESULTS}/timings"
  CFG=${TESTDIR}/configs/wrk_${STARTTIME}.lua
  replace_all ${TESTDIR}/configs/wrk.lua ${CFG}
  echo "${TESTNAME}: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency --script ${CFG} ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency --script ${CFG} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _RPS=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep '^Requests/sec:' |awk '{print $2}' |stripdecimals`
  _RTTAVG=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |duration2ms |stripdecimals`
  _REQUESTS=`grep ' requests in ' ${RESULTS}/stdout.log |tail -1 |awk '{print $1}'`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX=`grep -A 2 'Thread stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $4}' |duration2ms |stripdecimals`
  _RTTp50=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="50%"{print $2}' |duration2ms |stripdecimals`
  _RTTp75=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="75%"{print $2}' |duration2ms |stripdecimals`
  _RTTp90=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="90%"{print $2}' |duration2ms |stripdecimals`
  _RTTp95="-"
  _RTTp99=`grep -A 4 'Latency distribution' ${RESULTS}/stdout.log |awk '$1=="99%"{print $2}' |duration2ms |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

staticurltests() {
  apachebench_static
  boom_static
  wrk_static
  artillery_static
  vegeta_static
  siege_static
  tsung_static
  jmeter_static
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/apachebench_static/timings \
      ${LOGDIR}/boom_static/timings \
      ${LOGDIR}/wrk_static/timings \
      ${LOGDIR}/artillery_static/timings \
      ${LOGDIR}/vegeta_static/timings \
      ${LOGDIR}/siege_static/timings \
      ${LOGDIR}/tsung_static/timings \
      ${LOGDIR}/jmeter_static/timings \
      >${LOGDIR}/staticurltests.timings
  echo ""
  echo "------------------------------------------------- Static URL test results --------------------------------------------------"
  report ${LOGDIR}/staticurltests.timings "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "----------------------------------------------------------------------------------------------------------------------------"
  echo ""
}

scriptingtests() {
  locust_scripting
  grinder_scripting
  #gatling_scripting
  wrk_scripting
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/locust_scripting/timings \
      ${LOGDIR}/grinder_scripting/timings \
      ${LOGDIR}/wrk_scripting/timings \
      >${LOGDIR}/scriptingtests.timings
  echo ""
  echo "------------------------------------------------- Scripting test results --------------------------------------------------"
  report ${LOGDIR}/scriptingtests.timings "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "---------------------------------------------------------------------------------------------------------------------------"
  echo ""
}

alltests() {
  staticurltests
  scriptingtests
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/staticurltests.timings \
      ${LOGDIR}/scriptingtests.timings \
      >${LOGDIR}/alltests.timings
  echo ""
  echo "---------------------------------------------------- All test results -----------------------------------------------------"
  report ${LOGDIR}/alltests.timings "Testname Requests Errors RPS RTTMIN RTTMAX RTTAVG RTT50 RTT75 RTT90 RTT95 RTT99"
  echo "---------------------------------------------------------------------------------------------------------------------------"
  echo ""
}


clear
while [ 1 ]
do
  echo ""
  echo "################################################"
  echo "#  Load Impact load generator test suite V1.0  #"
  echo "################################################"
  echo ""
  echo "1. Choose target URL (current: ${TARGETURL})"
  echo "2. Set concurrent requests/VUs (current: ${CONCURRENT})"
  echo "3. Set total number of requests (current: ${REQUESTS})"
  echo "4. Set test duration (current: ${DURATION})"
  echo ""
  echo "5. Run all tests"
  echo "6. Run all static-URL tests"
  echo "7. Run all scripting tests"
  echo ""
  echo "a. Run Apachebench static-URL test"
  echo "b. Run Wrk static-URL test"
  echo "c. Run Boom static-URL test"
  echo "d. Run Artillery static-URL test"
  echo "e. Run Vegeta static-URL test"
  echo "f. Run Siege static-URL test"
  echo "g. Run Tsung static-URL test"
  echo "h. Run Jmeter static-URL test"
  echo ""
  echo "A. Run Locust scripting test"
  echo "B. Run Grinder scripting test"
  echo "C. Run Gatling scripting test"
  echo "D. Run Wrk scripting test"
  echo ""
  echo "X. Escape to bash"
  echo ""
  echo -n "Select (1-4,a-h,A-D,X): "
  read ans
  # Record start time
  export STARTTIME=`date +%y%m%d-%H%M%S`
  case $ans in
    1)
      echo -n "Enter target URL: "
      read ans
      export TARGETURL=$ans
      ;;
    2)
      echo -n "Enter # of concurrent requests: "
      read ans
      export CONCURRENT=$ans
      ;;
    3)
      echo -n "Enter total # of requests: "
      read ans
      export REQUESTS=$ans
      ;;
    4)
      echo -n "Enter test duration: "
      read ans
      export DURATION=$ans
      ;;

    5)
      [ "${TARGETURL}x" != "x" ] && alltests
      ;;
    6)
      [ "${TARGETURL}x" != "x" ] && staticurltests
      ;;
    7)
      [ "${TARGETURL}x" != "x" ] && scriptingtests
      ;;
    a)
      [ "${TARGETURL}x" != "x" ] && apachebench_static
      ;;
    b)
      [ "${TARGETURL}x" != "x" ] && wrk_static
      ;;
    c)
      [ "${TARGETURL}x" != "x" ] && boom_static
      ;;
    d)
      [ "${TARGETURL}x" != "x" ] && artillery_static
      ;;
    e)
      [ "${TARGETURL}x" != "x" ] && vegeta_static
      ;;
    f)
      [ "${TARGETURL}x" != "x" ] && siege_static
      ;;
    g)
      [ "${TARGETURL}x" != "x" ] && tsung_static
      ;;
    h)
      [ "${TARGETURL}x" != "x" ] && jmeter_static
      ;;
    A)
      [ "${TARGETURL}x" != "x" ] && locust_scripting
      ;;
    B)
      [ "${TARGETURL}x" != "x" ] && grinder_scripting
      ;;
    C)
      [ "${TARGETURL}x" != "x" ] && gatling_scripting
      ;;
    D)
      [ "${TARGETURL}x" != "x" ] && wrk_scripting
      ;;
    X)
      /bin/bash
      ;;
  esac
done
