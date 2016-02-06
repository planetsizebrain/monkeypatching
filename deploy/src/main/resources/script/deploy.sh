#!/bin/bash

# Enable the use of exclusions !() in copy and delete commands
shopt -s extglob

# Init
FILE="/tmp/out.$$"
GREP="/bin/grep"

while [[ $# > 1 ]]
do
key="$1"

case $key in
	-r|--repository)
	REPOSITORY="$2"
	shift # past argument
	;;
	-v|--version)
	RELEASE_VERSION="$2"
	shift # past argument
	;;
	-e|--environment)
	ENVIRONMENT="$2"
	shift # past argument
	;;
	*)
		# unknown option
	;;
esac
shift
done

REPO_BASE_URL="https://repository.planetsizebrain.be/nexus/content/repositories"

NEXUS_USER='deployer'
NEXUS_PASSWORD='deployer'

LIFERAY_VERSION='6.2.10.10'
TOMCAT_VERSION='tomcat-7.0.42'
LIFERAY_HOME="liferay-portal-$LIFERAY_VERSION"
TOMCAT_HOME="$LIFERAY_HOME/$TOMCAT_VERSION"

GROUP_ID='be.planetsizebrain.liferay'
ARTIFACT_ID='deploy'
ASSEMBLY_ID='portal-release-bundle'

GROUP_ID_PATH="$(echo $GROUP_ID | sed 's/\./\//g')"

LIFERAY_STOP_TIMEOUT=300
LIFERAY_START_TIMEOUT=900

if [ -z "$REPOSITORY"  ]; then
	echo "Which repository do you want to use?"
	select opt in "Snapshot" "Release" "Local (.m2 folder)"; do
		case "$REPLY" in
			1 ) REPOSITORY=snapshots; break;;
			2 ) REPOSITORY=releases; break;;
			3 ) REPOSITORY=local; break;;
		esac
	done
	echo ''
fi


if [ -z "$RELEASE_VERSION" ]; then
	echo '--------------------------------------'
	echo ' Choose an artifact version to deploy '
	echo '--------------------------------------'

	if [ $REPOSITORY == "local" ]; then
		release_versions=`cat ~/.m2/repository/$GROUP_ID_PATH/$ARTIFACT_ID/maven-metadata-local.xml | grep '<version>' | sed -e 's#.*<version>\(.*\)</version>.*#\1#g'`
	else
		release_versions=`curl -k -s -L --user $NEXUS_USER:$NEXUS_PASSWORD $REPO_BASE_URL/$REPOSITORY/$GROUP_ID_PATH/$ARTIFACT_ID/maven-metadata.xml | grep '<version>' | sed -e 's#.*<version>\(.*\)</version>.*#\1#g'`
	fi
	select v in $release_versions; do
		RELEASE_VERSION="$v" ;break
	done
fi


if [ $REPOSITORY == "snapshots" ]; then
	release_version_id_meta="$REPO_BASE_URL/$REPOSITORY/$GROUP_ID_PATH/$ARTIFACT_ID/$RELEASE_VERSION/maven-metadata.xml"
	TIMESTAMP=`curl -k -s -L --user $NEXUS_USER:$NEXUS_PASSWORD $release_version_id_meta | grep '<timestamp>' | sed -e 's#.*<timestamp>\(.*\)</timestamp>.*#\1#g'`
	BUILD_NO=`curl -k -s -L --user $NEXUS_USER:$NEXUS_PASSWORD $release_version_id_meta | grep '<buildNumber>' | sed -e 's#.*<buildNumber>\(.*\)</buildNumber>.*#\1#g'`
	version_without_snapshot=$(echo $RELEASE_VERSION | sed 's/-SNAPSHOT//g')
	RELEASE_VERSION_ID="$version_without_snapshot-$TIMESTAMP-$BUILD_NO"
else
	RELEASE_VERSION_ID=$RELEASE_VERSION
fi


echo ''
RELEASE_DIR="release-$RELEASE_VERSION"
RELEASE_ZIP="$RELEASE_DIR.zip"

if [ -z "$ENVIRONMENT" ]; then
	echo '-----------------------------------------'
	echo ' Which environment are you releasing on? '
	echo '-----------------------------------------'
	read -p "Environment: " ENVIRONMENT
	echo ''
fi

if [ $ENVIRONMENT != "local" ] && [ $ENVIRONMENT != "dev" ]; then
	echo '----------------------------------'
	echo ' Which node are you releasing on? '
	echo '----------------------------------'
	read -p "Node: " NODE
	echo ''
fi

ENV_DIRECTORY="$RELEASE_DIR/liferay/environmentSpecific/$ENVIRONMENT"

# Shutdown server
t=$LIFERAY_STOP_TIMEOUT

if ps axg | grep -v grep | grep liferay-portal > /dev/null ; then
	echo '[INFO] Liferay is running, stopping it...'

	./$TOMCAT_HOME/bin/catalina.sh stop

	while ps axg | grep -v grep | grep liferay-portal > /dev/null && [ $t -gt 0 ] ; do
		sleep 1
		: $((t--))
	done
fi

if [[ $t = 0 ]] ; then
	echo '[INFO] Liferay could not be shutdown gracefully. Killing the process.'
	kill $(ps aux | grep 'liferay-portal' | awk '{print $2}')
fi

# Backup
echo '[INFO] Backing up indexes, logs & license...'
mkdir backup
mkdir backup/lucene
mkdir backup/document_library
mkdir backup/logs
mkdir backup/license

mv $LIFERAY_HOME/data/lucene/* backup/lucene
mv $LIFERAY_HOME/data/license/* backup/license
mv $TOMCAT_HOME/logs/* backup/logs

# Remove old Liferay
echo '[INFO] Removing old Liferay bundle...'
rm -rf $LIFERAY_HOME

# Download and unzip Liferay
if [ ! -f /tmp/$LIFERAY_HOME.zip ]
then
	echo '[INFO] Downloading Liferay bundle...'
	wget --auth-no-challenge --no-check-certificate --user $NEXUS_USER --password $NEXUS_PASSWORD -O /tmp/$LIFERAY_HOME.zip "$REPO_BASE_URL/releases-ext/com/liferay/portal-tomcat/$LIFERAY_VERSION/portal-tomcat-$LIFERAY_VERSION.zip"
fi

echo '[INFO] Unzipping and renaming Liferay bundle...'
unzip -qq /tmp/$LIFERAY_HOME.zip -d .
mv liferay-portal-* $LIFERAY_HOME

# Download and unzip release bundle
echo '[INFO] Downloading release bundle '$RELEASE_VERSION'...'

if [ $REPOSITORY == "local" ]; then
	cp ~/.m2/repository/$GROUP_ID_PATH/$ARTIFACT_ID/$RELEASE_VERSION/$ARTIFACT_ID-$RELEASE_VERSION-$ASSEMBLY_ID.zip $RELEASE_ZIP
else
	release_bundle_url="$REPO_BASE_URL/$REPOSITORY/$GROUP_ID_PATH/$ARTIFACT_ID/$RELEASE_VERSION/$ARTIFACT_ID-$RELEASE_VERSION_ID-$ASSEMBLY_ID.zip"
	wget --auth-no-challenge --no-check-certificate --user $NEXUS_USER --password $NEXUS_PASSWORD -O $RELEASE_ZIP $release_bundle_url
fi

echo '[INFO] Unzipping release bundle...'
unzip -qq $RELEASE_ZIP -d $RELEASE_DIR
rm $RELEASE_ZIP

# Unzip Liferay WAR overlay
echo '[INFO] Unpacking Liferay WAR to webapps/ROOT...'
if [ ! -d "$TOMCAT_HOME/webapps/ROOT" ]; then
	mkdir -v $TOMCAT_HOME/webapps/ROOT
else
	rm -r -v $TOMCAT_HOME/webapps/ROOT/*
fi
unzip -qq -o $RELEASE_DIR/wars/portal-war-overlay.war -d $TOMCAT_HOME/webapps/ROOT

# Backup patches
echo '[INFO] Backing up patches...'
mkdir backup/patches
mv $LIFERAY_HOME/patching-tool/patches/* backup/patches

# Download latest patching tool
patch_tool_url="$REPO_BASE_URL/releases-ext/com/liferay/patches/patching-tool/maven-metadata.xml"
PATCHING_TOOL_VERSION=`curl -k -s -L --user $NEXUS_USER:$NEXUS_PASSWORD $patch_tool_url | grep '<latest>' | sed -e 's#.*<latest>\(.*\)</latest>.*#\1#g'`

echo '[INFO] Downloading patching tool v'$PATCHING_TOOL_VERSION'...'
wget --auth-no-challenge --no-check-certificate --user $NEXUS_USER --password $NEXUS_PASSWORD -O patching-tool.zip "$REPO_BASE_URL/releases-ext/com/liferay/patches/patching-tool/$PATCHING_TOOL_VERSION/patching-tool-$PATCHING_TOOL_VERSION.zip"

echo '[INFO] Installing and configuring patching tool...'
rm -rf $LIFERAY_HOME/patching-tool
unzip -qq patching-tool.zip -d $LIFERAY_HOME
rm patching-tool.zip
chmod 755 $LIFERAY_HOME/patching-tool/patching-tool.sh
./$LIFERAY_HOME/patching-tool/patching-tool.sh auto-discovery

# Restore backup
echo '[INFO] Restoring documents, indexes, logs and patches...'
mkdir $LIFERAY_HOME/data/lucene
mkdir $LIFERAY_HOME/data/license
mv backup/lucene/* $LIFERAY_HOME/data/lucene
mv backup/logs/* $TOMCAT_HOME/logs
mv backup/patches/* $LIFERAY_HOME/patching-tool/patches
mv backup/license/* $LIFERAY_HOME/data/license
rm -rf backup

echo '[INFO] Cleaning Tomcat directories...'
rm -rf $TOMCAT_HOME/conf/Catalina/localhost/!(ROOT.xml)
rm -rf $TOMCAT_HOME/webapps/!(ROOT)
rm -rf $TOMCAT_HOME/temp/*
rm -rf $TOMCAT_HOME/work

echo 'Overlaying custom Tomcat configuration files...'
cp -rf $RELEASE_DIR/liferay/general/tomcat/* $TOMCAT_HOME
cp -rf $ENV_DIRECTORY/portal-ext.properties $TOMCAT_HOME/..
cp -rf $ENV_DIRECTORY/lcs-cluster-entry-token* $LIFERAY_HOME/data
cp -rf $ENV_DIRECTORY/tomcat/* $TOMCAT_HOME
chmod 755 $TOMCAT_HOME/bin/setenv.sh

echo 'Installing patches...'
cp $RELEASE_DIR/patches/*.zip $LIFERAY_HOME/patching-tool/patches
./$LIFERAY_HOME/patching-tool/patching-tool.sh install
./$LIFERAY_HOME/patching-tool/patching-tool.sh update-plugins

echo 'Copying custom plugins to deploy directory...'
mkdir $LIFERAY_HOME/deploy
cp $RELEASE_DIR/wars/!(portal-war-overlay.war) $LIFERAY_HOME/deploy

echo 'Copying license file...'
cp $ENV_DIRECTORY/license.xml $LIFERAY_HOME/deploy

echo 'Removing temporary data...'
rm -r $RELEASE_DIR

echo 'Removing .bat files...'
rm -r $TOMCAT_HOME/bin/*.bat

# Restart server
echo ''
echo '[INFO] Restarting server...'

start_time=$(date +"%s")

./$TOMCAT_HOME/bin/catalina.sh start

tail -fn1 $TOMCAT_HOME/logs/catalina.out | while read LOGLINE || sleep 1;
do
	[[ "${LOGLINE}" == *"Server startup"* ]] && pkill -P $$ tail && echo '[INFO] Server restarted' && break;
	now_time=$(date +"%s")
	[[ $((now_time-start_time)) -gt $LIFERAY_START_TIMEOUT ]] && pkill -P $$ tail && echo '[INFO] Server restart timeout' && break;
done

echo ''
echo '[INFO] RELEASE COMPLETED !'