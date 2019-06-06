#!/bin/bash

source /etc/profile 
source ~/.bashrc 

LANG="zh_CN.UTF-8"
export LANG

# 使用配置文件并获取配置参数
source mysql_backup.ini

#删除40天之前的备份目录
#find "$backup_dir/bak" -maxdepth 1 -mtime +40 -name "20*" -exec rm -rf {} \;

#拷贝备份文件到远程服务器
#'scp' -r $backup_log_path 172.20.120.23:/home/mysql/mysql_backup_221/
#scp -r $backup_dir'/'$backup_name'/' 172.20.120.23:/home/mysql/mysql_backup_221/

#删除keep_days_log天之前的binlog日志
mysql --host=$host --user=$user --password=$password --port=$port -e "PURGE BINARY LOGS BEFORE DATE_SUB(DATE(NOW()),INTERVAL $keep_days_log DAY)"

#获取最新的增量备份路径保存到日志文件(按修改时间降序排列文件，并取出第二行结果)
backup_name=`ls -lnt $backup_dir | awk 'NR==2 {print $9}'`

#备份基础数据
mysqldump --host=$host --user=$user --password=$password --port=$port cat_integ > $backup_dir'/'$backup_name'/cat_integ.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port cat_mdm > $backup_dir'/'$backup_name'/cat_mdm.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port disconf > $backup_dir'/'$backup_name'/disconf.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port otter > $backup_dir'/'$backup_name'/otter.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port user_scheduler > $backup_dir'/'$backup_name'/user_scheduler.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port db_uc_merged > $backup_dir'/'$backup_name'/db_uc_merged.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port node_integ > $backup_dir'/'$backup_name'/node_integ.sql'
mysqldump --host=$host --user=$user --password=$password --port=$port node_mdm > $backup_dir'/'$backup_name'/node_mdm.sql'

#定时清理数据脚本
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table otter.table_history_stat;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table otter.log_record;"

mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.os_diskio_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_slow_query_review_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_processlist;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_connected;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.os_net_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.os_disk_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_status_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_slow_query_review;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.mysql_replication_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.alarm_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.os_status_history;"
mysql --host=$host --user=$user --password=$password --port=$port -e "truncate table user_lepus.alarm_temp;"

