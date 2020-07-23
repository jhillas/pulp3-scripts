#!/bin/env bash
##########################################
# Script: delete_pulp3_rpm_repo.sh
#
##########################################

set -e

echo "Type the name of the rpm repository"
read REPONAME
export REPONAME=$REPONAME

echo "Delete rpm repo named: $REPONAME ? (y/n)"
read yn
if [ ${yn} != y ]; then
  echo "You selected ${yn}, exiting"
  exit
fi
echo

export BASE_ADDR=${BASE_ADDR:-http://localhost:24817}
export CONTENT_ADDR=${CONTENT_ADDR:-http://localhost:24816}
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings

# Parse out pulp_href using http and jq
export REPO_HREF=$(http GET $BASE_ADDR/pulp/api/v3/repositories/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')

# Delete Repository
http DELETE $BASE_ADDR$REPO_HREF

exit