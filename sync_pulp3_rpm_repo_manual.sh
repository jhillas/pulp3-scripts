#!/bin/env bash
##########################################
# Script: sync_pulp3_rpm_repo_manual.sh
#
##########################################

set -e

echo "Type the name of the rpm repository"
read REPONAME
export REPONAME=$REPONAME
echo

echo "Sync rpm repo named: $REPONAME ? (y/n)"
read yn
if [ ${yn} != y ]; then
  echo "You selected ${yn}, exiting"
  exit
fi
echo

export BASE_ADDR=${BASE_ADDR:-http://localhost:24817}
export CONTENT_ADDR=${CONTENT_ADDR:-http://localhost:24816}
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings

wait_until_task_finished() {
  echo "Polling the task until it has reached a final state."
  local task_url=$1
  while true
    do
      local response=$(http $task_url)
      local state=$(jq -r .state <<< ${response})
      jq . <<< "${response}"
      case ${state} in
          failed|canceled)
              echo "Task in final state: ${state}"
              exit 1
              ;;
          completed)
              echo "$task_url complete."
              break
              ;;
          *)
              echo "Still waiting..."
              sleep 1
              ;;
      esac
  done
}

# Store repo href in variable
export REPO_HREF=$(http GET $BASE_ADDR/pulp/api/v3/repositories/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')

# Store remote repo href in variable
export REMOTE_HREF=$(http $BASE_ADDR/pulp/api/v3/remotes/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')

# Sync repository 
export TASK_URL=$(http POST $BASE_ADDR$REPO_HREF'sync/' remote=$REMOTE_HREF | jq -r '.task')

# Poll the task (here we use a function defined in docs/_scripts/base.sh)
wait_until_task_finished $BASE_ADDR$TASK_URL

exit