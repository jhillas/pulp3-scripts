#!/bin/env bash
##########################################
# Script: sync_all_pulp3_rpm_repo.sh
#
##########################################

set -e

TMPDIR=$(mktemp -d)
cd ${TMPDIR}

export BASE_ADDR=${BASE_ADDR:-http://localhost:24817}
export CONTENT_ADDR=${CONTENT_ADDR:-http://localhost:24816}
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings
export LOG=${TMPDIR}/pulp_sync_$(date +%Y%m%d_%H%M).log

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

for REPONAME in $(http GET $BASE_ADDR/pulp/api/v3/repositories/rpm/rpm/| jq -r '.results[] | .name')
  do
    export REPONAME=$REPONAME
    echo "Syncing $REPONAME $(date +%Y%m%d_%H%M)" >> ${LOG}
    export REPO_HREF=$(http GET http://localhost:24817/pulp/api/v3/repositories/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')
    echo "HREF: $REPO_HREF" >> ${LOG}
    export REMOTE_HREF=$(http $BASE_ADDR/pulp/api/v3/remotes/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')
    echo "REMOTE HREF: $REMOTE_HREF" >> ${LOG}
    export TASK_URL=$(http POST $BASE_ADDR$REPO_HREF'sync/' remote=$REMOTE_HREF | jq -r '.task')
    echo "TASK_URL: $TASK_URL" >> ${LOG}
    wait_until_task_finished $BASE_ADDR$TASK_URL >> ${LOG}
    echo "################################################" >> ${LOG}
done

exit
