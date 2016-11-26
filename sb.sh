#!/bin/bash
#
# 2015-2017 (c) Nuno Tavares <nuno.tavares@synrix.com>
#
# TESTED ON: 
# 2016-1126 CentOS-7 (7.2.1511)
#


#rm sb.sh

HOST=$1
PLAN=$2
EMAIL=$3
COST=$4
PRIVATE=$5

# 
# Select here available tests:
# traceroute ping download dd fio ioping unixbench sysbench
#
ENABLED_TESTS="traceroute ping download dd fio ioping unixbench sysbench"

#
# Specify here if you want to run benchmarks in foreground,
# otherwise it will be pushed to the background (useful for cron)
#
RUN_IN_FOREGROUND="false"

#
# Change this variable if you want to perform I/O tests in a specific place
#
IOMOUNTPOINT=.

#
# Execute the tests but do not submit, this is for debugging
#
DRY_RUN=false

PID=`cat ~/.sb-pid 2>/dev/null`
if [ -e "~/.sb-pid" ] && ps -p $PID >&- ; then
  echo "CloudBench job is already running (PID: $PID)"
  exit 0
fi

echo "Checking for required dependencies"

function requires() {
  if [ `$1 >/dev/null; echo $?` -ne 0 ]; then
    TO_INSTALL="$TO_INSTALL $2"
  fi 
}
function requires_command() { 
  requires "which $1" $1 
}


TO_INSTALL=""

if [ `which apt-get >/dev/null 2>&1; echo $?` -ne 0 ]; then
  PACKAGE_MANAGER='yum'

  requires 'yum list installed kernel-devel' 'kernel-devel'
  requires 'yum list installed libaio-devel' 'libaio-devel'
  requires 'yum list installed gcc-c++' 'gcc-c++'
  requires 'perl -MTime::HiRes -e 1' 'perl-Time-HiRes'
else
  PACKAGE_MANAGER='apt-get'
  MANAGER_OPTS='--fix-missing'
  UPDATE='apt-get update'

  requires 'dpkg -s build-essential' 'build-essential'
  requires 'dpkg -s libaio-dev' 'libaio-dev'
  requires 'perl -MTime::HiRes -e 1' 'perl'
fi

#rm -rf sb-bench
mkdir -p sb-bench
cd sb-bench

requires_command 'gcc'
requires_command 'make'
requires_command 'curl'

if [ "`whoami`" != "root" ]; then
  SUDO='sudo'
fi

if [ "$TO_INSTALL" != '' ]; then
  echo "Using $PACKAGE_MANAGER to install$TO_INSTALL"
  if [ "$UPDATE" != '' ]; then
    echo "Doing package update"
    $SUDO $UPDATE
  fi 
  $SUDO $PACKAGE_MANAGER install -y $TO_INSTALL $MANAGER_OPTS
fi

UPLOAD_ENDPOINT='http://cloudbench.devleaseweb.com/op/postbench.php'
KEY=87f1921888674cb99c05bac8e9f3b84b

# args: [name] [target dir] [filename] [url]
function require_download() {
  if ! [ -e "`pwd`/$2" ]; then
    echo "Downloading $1..."
    wget -q --no-check-certificate -O - $3 | tar -xzf -
  fi
}

for test_on in $ENABLED_TESTS ; do
   eval TESTON_$test_on=true
done

###############################################################################
#                                                                             #
###############################################################################

###############################################################################
# PING                                                                        #
###############################################################################
PING_REMOTES="cachefly.cachefly.net"


###############################################################################
# Traceroute                                                                  #
###############################################################################
TRACEROUTE_REMOTES="$PING_REMOTES"
if [ "$TESTON_traceroute" = "true" ] ; then
   requires_command 'traceroute'
fi

###############################################################################
# UnixBench                                                                   #
###############################################################################
UNIX_BENCH_VERSION=5.1.3
UNIX_BENCH_DIR=UnixBench-$UNIX_BENCH_VERSION
if [ "$TESTON_unixbench" = "true" ] ; then
   require_download UnixBench $UNIX_BENCH_DIR https://github.com/Crowd9/Benchmark/raw/master/UnixBench$UNIX_BENCH_VERSION-patched.tgz
   mv -f UnixBench $UNIX_BENCH_DIR 2>/dev/null
fi


###############################################################################
# SysBench                                                                    #
###############################################################################
SYSBENCH_VERSION=0.4.12.7
SYSBENCH_DIR=sysbench-$SYSBENCH_VERSION
SYSBENCH_THREADS_ITERS="1 2 4"
if [ "$TESTON_sysbench" = "true" ] ; then
   require_download sysbench $SYSBENCH_DIR http://downloads.mysql.com/source/sysbench-$SYSBENCH_VERSION.tar.gz
fi

###############################################################################
# IOPing                                                                      #
###############################################################################
IOPING_VERSION=0.9
IOPING_DIR=ioping-$IOPING_VERSION
if [ "$TESTON_ioping" = "true" ] ; then
   require_download IOPing $IOPING_DIR https://github.com/koct9i/ioping/releases/download/v$IOPING_VERSION/ioping-$IOPING_VERSION.tar.gz
fi

###############################################################################
# FIO                                                                         #
###############################################################################
FIO_VERSION=2.0.9
FIO_DIR=fio-$FIO_VERSION
if [ "$TESTON_fio" = "true" ] ; then
   require_download FIO $FIO_DIR https://github.com/Crowd9/Benchmark/raw/master/fio-$FIO_VERSION.tar.gz
   cat > $FIO_DIR/reads.ini << EOF
[global]
randrepeat=1
ioengine=libaio
bs=4k
ba=4k
size=1G
direct=1
gtod_reduce=1
norandommap
iodepth=64
numjobs=1

[randomreads]
startdelay=0
filename=$IOMOUNTPOINT/sb-io-test
readwrite=randread
EOF
   cat > $FIO_DIR/writes.ini << EOF
[global]
randrepeat=1
ioengine=libaio
bs=4k
ba=4k
size=1G
direct=1
gtod_reduce=1
norandommap
iodepth=64
numjobs=1

[randomwrites]
startdelay=0
filename=$IOMOUNTPOINT/sb-io-test
readwrite=randwrite
EOF
fi


cat > run-upload.sh << EOF
#!/bin/bash

echo "
###############################################################################
#                                                                             #
#             Installation(s) complete.  Benchmarks starting...               #
#                                                                             #
#  Running Benchmark as a background task. This can take several hours.       #
#  This scripts runs standalone, and the results will be automatically        #
#  submitted to LEASEWEB.                                                     #
#                                                                             #
###############################################################################
"
ENABLED_TESTS="$ENABLED_TESTS"
IOMOUNTPOINT="$IOMOUNTPOINT"
DRY_RUN="$DRY_RUN"

for test_on in \$ENABLED_TESTS ; do
   eval TESTON_\$test_on=true
done

>sb-output.log

echo "Checking server stats..."
echo "Distro:
#\`[ -e /etc/os-release ] && grep ^PRETTY_NAME /etc/os-release | awk -F '"' '{print \$2;}' || cat /etc/issue 2>&1\`
\`cat /etc/issue 2>&1\`
CPU Info:
\`cat /proc/cpuinfo 2>&1\`
Disk space: 
\`df --total 2>&1\`
Free: 
\`free 2>&1\`" >> sb-output.log


rm -f \$IOMOUNTPOINT/sb-io-test
if [ "\$TESTON_dd" != "true" ] ; then
   echo "Skipping test: dd"
else
   echo "Running dd I/O benchmark..."
   echo "dd 1Mx1k fdatasync: \`dd if=/dev/zero of=\$IOMOUNTPOINT/sb-io-test bs=1M count=1k conv=fdatasync 2>&1\`" >> sb-output.log
   echo "dd 64kx16k fdatasync: \`dd if=/dev/zero of=\$IOMOUNTPOINT/sb-io-test bs=64k count=16k conv=fdatasync 2>&1\`" >> sb-output.log
   echo "dd 1Mx1k dsync: \`dd if=/dev/zero of=\$IOMOUNTPOINT/sb-io-test bs=1M count=1k oflag=dsync 2>&1\`" >> sb-output.log
   echo "dd 64kx16k dsync: \`dd if=/dev/zero of=\$IOMOUNTPOINT/sb-io-test bs=64k count=16k oflag=dsync 2>&1\`" >> sb-output.log
fi


rm -f \$IOMOUNTPOINT/sb-io-test
if [ "\$TESTON_ioping" != "true" ] ; then
   echo "Skipping test: ioping"
else
   echo "Running IOPing I/O benchmark..."
   echo " + compiling..."
   cd $IOPING_DIR
   make >> ../sb-output.log 2>&1
   echo " + running..."
   echo "IOPing I/O: \`./ioping -c 10 \$IOMOUNTPOINT 2>&1 \`
   IOPing seek rate: \`./ioping -RD \$IOMOUNTPOINT 2>&1 \`
   IOPing sequential: \`./ioping -RL \$IOMOUNTPOINT 2>&1\`
   IOPing cached: \`./ioping -RC \$IOMOUNTPOINT 2>&1\`" >> ../sb-output.log
   cd ..
fi



rm -f \$IOMOUNTPOINT/sb-io-test
if [ "\$TESTON_fio" != "true" ] ; then
   echo "Skipping test: fio"
else
   echo "Running FIO benchmark..."
   echo " + compiling..."
   cd $FIO_DIR
   make >> ../sb-output.log 2>&1

   echo " + running..."
   echo "FIO random reads:
   \`./fio reads.ini 2>&1\`
   Done" >> ../sb-output.log
   
   echo "FIO random writes:
   \`./fio writes.ini 2>&1\`
   Done" >> ../sb-output.log
   
   rm -f \$IOMOUNTPOINT/sb-io-test 2>/dev/null
   cd ..
fi



function download_benchmark() {
  echo "Benchmarking download from \$1 (\$2)"
  DOWNLOAD_SPEED=\`wget -O /dev/null \$2 2>&1 | awk '/\\/dev\\/null/ {speed=\$3 \$4} END {gsub(/\\(|\\)/,"",speed); print speed}'\`
  echo "Got \$DOWNLOAD_SPEED"
  echo "Download \$1: \$DOWNLOAD_SPEED" >> sb-output.log 2>&1
}

if [ "\$TESTON_download" != "true" ] ; then
   echo "Skipping test: download"
else
   echo "Running download (bandwidth) benchmark..."
   download_benchmark 'Cachefly' 'http://cachefly.cachefly.net/100mb.test'
   download_benchmark 'Linode, Atlanta, GA, USA' 'http://speedtest.atlanta.linode.com/100MB-atlanta.bin'
   download_benchmark 'Linode, Dallas, TX, USA' 'http://speedtest.dallas.linode.com/100MB-dallas.bin'
   download_benchmark 'Linode, Tokyo, JP' 'http://speedtest.tokyo.linode.com/100MB-tokyo.bin'
   download_benchmark 'Linode, London, UK' 'http://speedtest.london.linode.com/100MB-london.bin'
   download_benchmark 'OVH, Paris, France' 'http://proof.ovh.net/files/100Mio.dat'
   download_benchmark 'SmartDC, Rotterdam, Netherlands' 'http://mirror.i3d.net/100mb.bin'
   download_benchmark 'Hetzner, Nuernberg, Germany' 'http://hetzner.de/100MB.iso'
   download_benchmark 'iiNet, Perth, WA, Australia' 'http://ftp.iinet.net.au/test100MB.dat'
   download_benchmark 'MammothVPS, Sydney, Australia' 'http://www.mammothvpscustomer.com/test100MB.dat'
   download_benchmark 'Leaseweb, Haarlem, NL' 'http://mirror.nl.leaseweb.net/speedtest/100mb.bin'
   download_benchmark 'Leaseweb, Manassas, VA, USA' 'http://mirror.us.leaseweb.net/speedtest/100mb.bin'
   download_benchmark 'Softlayer, Singapore' 'http://speedtest.sng01.softlayer.com/downloads/test100.zip'
   download_benchmark 'Softlayer, Seattle, WA, USA' 'http://speedtest.sea01.softlayer.com/downloads/test100.zip'
   download_benchmark 'Softlayer, San Jose, CA, USA' 'http://speedtest.sjc01.softlayer.com/downloads/test100.zip'
   download_benchmark 'Softlayer, Washington, DC, USA' 'http://speedtest.wdc01.softlayer.com/downloads/test100.zip'
fi

if [ "\$TESTON_traceroute" != "true" ] ; then
   echo "Skipping test: traceroute"
else
   echo "Running traceroute..."
   for remote in $TRACEROUTE_REMOTES ; do
      echo "Traceroute (\$remote): \`traceroute -n \$remote 2>&1\`" >> sb-output.log
   done
fi


if [ "\$TESTON_ping" != "true" ] ; then
   echo "Skipping test: ping"
else
   echo "Running ping benchmark..."
   for remote in $PING_REMOTES ; do
       echo "Pings (\$remote): \`ping -c 10 \$remote 2>&1\`" >> sb-output.log
   done
fi

if [ "\$TESTON_unixbench" != "true" ] ; then
   echo "Skipping test: unixbench"
else
   echo "Running UnixBench benchmark..."
   cd $UNIX_BENCH_DIR
   ./Run -c 1 -c `grep -c processor /proc/cpuinfo` >> ../sb-output.log 2>&1
   cd ..
fi


if [ "\$TESTON_sysbench" != "true" ] ; then
   echo "Skipping test: sysbench"
else
   echo "Running sysbench..."
   cd $SYSBENCH_DIR
   echo " + compiling..."
   ./configure --without-mysql >> ../sb-output.log 2>&1
   make >> ../sb-output.log 2>&1
   if [ -e sysbench/sysbench ] ; then
      echo " + running..."
      for th in $SYSBENCH_THREADS_ITERS ; do
         echo "### SYSBENCH:BEGIN test=threads num-threads=\$th" >> ../sb-output.log
            sysbench/sysbench --test=threads --num-threads=\$th --thread-locks=1 --max-requests=262144 --max-time=600s run >> ../sb-output.log 2>&1
         echo "### SYSBENCH:END test=threads num-threads=\$th" >> ../sb-output.log
         echo "### SYSBENCH:BEGIN test=cpu num-threads=\$th" >> ../sb-output.log
            sysbench/sysbench --test=cpu --num-threads=\$th --cpu-max-prime=20000 --max-requests=524288 run >> ../sb-output.log 2>&1
         echo "### SYSBENCH:END test=cpu num-threads=\$th" >> ../sb-output.log
         echo "### SYSBENCH:BEGIN test=mutex num-threads=\$th" >> ../sb-output.log
            sysbench/sysbench --test=mutex --num-threads=\$th --mutex-num=4 --mutex-locks=524288 --mutex-loops=0 run >> ../sb-output.log 2>&1
         echo "### SYSBENCH:END test=mutex num-threads=\$th" >> ../sb-output.log
         echo "### SYSBENCH:BEGIN test=memory num-threads=\$th" >> ../sb-output.log
           sysbench/sysbench --test=memory --num-threads=\$th run >> ../sb-output.log 2>&1
         echo "### SYSBENCH:END test=memory num-threads=\$th" >> ../sb-output.log
      done
   fi
   cd ..
fi

if [ "\$DRY_RUN" = "true" ] ; then
   echo "DRY_RUN.SUBMIT: curl -s -F \"upload[upload_type]=unix-bench-output\" -F \"upload[data]=<sb-output.log\" -F \"upload[key]=$KEY\" $UPLOAD_ENDPOINT"
else
   echo "Uploading results..."
   RESPONSE=\`curl -s -F "upload[upload_type]=unix-bench-output" -F "upload[data]=<sb-output.log" -F "upload[key]=$KEY" $UPLOAD_ENDPOINT\`

   echo "Response: \$RESPONSE"
   echo "Completed! Your benchmark has been queued & will be delivered in a jiffy."
   kill -15 \`ps -p \$\$ -o ppid=\` &> /dev/null
   #rm -rf ../sb-bench
   rm -rf ~/.sb-pid

   exit 0
fi
EOF

chmod u+x run-upload.sh

>sb-output.log
if [ "$RUN_IN_FOREGROUND" = "true" ] ; then
   CMD="exec ./run-upload.sh 2>&1 | tee sb-output.log"
   if [ "$DRY_RUN" = "true" ] ; then
      echo "DRU_RUN.CMD: $CMD"
   else
      $CMD
   fi
else
   if [ "$DRY_RUN" = "true" ] ; then
      echo "DRY_RUN.CMD: nohup ./run-upload.sh >> sb-output.log 2>&1 & &> /dev/null"
   else
      nohup ./run-upload.sh >> sb-output.log 2>&1 & &> /dev/null
      echo $! > ~/.sb-pid
   fi
fi

#tail -n 25 -F sb-output.log

