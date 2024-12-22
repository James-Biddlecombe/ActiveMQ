### set custom PS1 ###
vi ~/.bashrc
    # add the below
    export PS1="\[$(tput bold)\]\[$(tput setaf 3)\]\u\[$(tput setaf 7)\]@\[$(tput setaf 1)\]\h\[$(tput setaf 7)\]:\[$(tput setaf 2)\]\w\[$(tput setaf 7)\]:\[$(tput sgr0)\]"
source ~/.bashrc
### initial updates after install ###
dnf update -y

### set selinux to permissive ###
vi /etc/selinux/config
#change the below from
SELINUX=enforcing
# to
SELINUX=permissive
# then also run a setenforce so we dont have to restart
setenforce 0

### install postgresql ###
dnf install postgresql-server.x86_64 -y
# initialise the database
/usr/bin/postgresql-setup --initd
# start and enable the postgres service
systemctl start postgresql.service && systemctl enable postgresql.service
# change to the postgres user and set the PS1
sudo su postgres
vi ~/.bashrc
    # add the below, blue is non root user for me
    export PS1="\[$(tput bold)\]\[$(tput setaf 3)\]\u\[$(tput setaf 7)\]@\[$(tput setaf 6)\]\h\[$(tput setaf 7)\]:\[$(tput setaf 2)\]\w\[$(tput setaf 7)\]:\[$(tput sgr0)\]"
source ~/.bashrc
# test that you can connect to the postgres instance as postgres user
psql
# exit psql
\q
# exit back to the root user
exit

### install activemq ###
# we will install the classic activemq
# https://activemq.apache.org/components/classic/
# create the activemq user that the application will run as
useradd activemq
# switch to the activemq user and set the PS! - blue for non root user
vi ~/.bashrc
    # add the below at the bottom, blue is non root user for me
    export PS1="\[$(tput bold)\]\[$(tput setaf 3)\]\u\[$(tput setaf 7)\]@\[$(tput setaf 6)\]\h\[$(tput setaf 7)\]:\[$(tput setaf 2)\]\w\[$(tput setaf 7)\]:\[$(tput sgr0)\]"
source ~/.bashrc
# change to activemq home directory
cd
# download activemq classic, we are using ActiveMQ Classic 6.1.4 and copy to server in /home/activemq/
scp apache-activemq-6.1.4-bin.tar.gz root@activemq.local.lab:/home/activemq/ 
# from the /home/activemq/ folder as the activemq user, uncompress the file
tar xvf apache-activemq-6.1.4-bin.tar.gz
#rename the folder from the version to just activemq
mv apache-activemq-6.1.4 activemq
# change back to the root user
exit

### install java 17 ###
dnf install java-17-openjdk-devel.x86_64 -y

### create the activemq database and user ###
su postgres
psql
CREATE ROLE amq LOGIN PASSWORD 'password' SUPERUSER;
CREATE DATABASE activemq WITH OWNER = amq;
GRANT CONNECT ON DATABASE activemq TO amq;
\q
# update the pg_hba.conf to trust the local connections
vi /var/lib/pgsql/data/pg_hba.conf
    # change these TWO lines from
    local   all             all                                     peer
    host    all             all             127.0.0.1/32            ident
    # to these TWO lines, its just replacing ident with trust
    local   all             all                                     trust
    host    all             all             127.0.0.1/32            trust
# restart the postgres service for the change to take effect
systemctl restart postgresql.service        # will need the root password as we are stil on the postgres user
# test that the user can connect to the database
psql -U amq -h 127.0.0.1 -d activemq -W
# go back to the root user
exit

### connect activemq to the postgres db ###
vi /home/activemq/activemq/conf/activemq.xml
# comment out the below
        <persistenceAdapter>
            <kahaDB directory="${activemq.data}/kahadb"/>
        </persistenceAdapter>
# add below the commented out
        <persistenceAdapter>
            <jdbcPersistenceAdapter dataSource="#postgres-ds"/>
        </persistenceAdapter>
# add the below bean after the credentials bean near the top of the activemq.xml
    <bean id="postgres-ds" class="org.postgresql.ds.PGSimpleDataSource">
        <property name="serverName" value="localhost"/>
        <property name="portNumber" value="5432"/>
        <property name="databaseName" value="activemq"/>
        <property name="user" value="amq"/>
        <property name="password" value="password"/>
    </bean>
    <bean id="jdbc" class="org.apache.activemq.store.jdbc.JDBCPersistenceAdapter">
        <property name="dataSource" ref="postgres-ds" />
        <property name="createTablesOnStartup" value="true" />
    </bean>
# update the jetty.xml for activemq to listen on all ipv4 network devices
vi /home/activemq/activemq/conf/jetty.xml
# update the below line in the jettyPort Bean
<property name="host" value="localhost"/>
# set it to
<property name="host" value="0.0.0.0"/>
# download the postgres jar and correct ownership
wget https://jdbc.postgresql.org/download/postgresql-42.6.0.jar
mv postgresql-42.6.0.jar /home/activemq/activemq/lib/
chown activemq:activemq /home/activemq/activemq/lib/postgresql-42.6.0.jar

### make activemq a service and start up ###
# ensure perms are correct for activemq
chown -R activemq:activemq /home/activemq/activemq
chmod -R 750 /home/activemq/activemq

vi /etc/systemd/system/activemq.service
# add the below to the service file
[Unit]
Description=Apache ActiveMQ
After=network.target

[Service]
Type=forking
User=activemq
Group=activemq
ExecStart=/home/activemq/activemq/bin/activemq start
ExecStop=/home/activemq/activemq/bin/activemq stop

[Install]
WantedBy=multi-user.target
# reload the systemd daemon and start up activemq
systemctl daemon-reload
systemctl enable activemq
systemctl start activemq

### open the port 8161 and 61616 on firewalld ###
firewall-cmd --permanent --add-port=8161/tcp
firewall-cmd --permanent --add-port=61616/tcp
firewall-cmd --reload

### try browse activemq admin from outside vm
http://activemq.local.lab:8161/admin/