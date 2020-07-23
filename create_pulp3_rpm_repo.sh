#!/bin/env bash
##########################################
# Script: create_pulp3_rpm_repo.sh
#
##########################################

set -e

echo "Type the name of the rpm repository"
read REPONAME
export REPONAME=$REPONAME
echo

echo "Type the URL of the rpm repository, for example: https://mirror.chpc.utah.edu/pub/centos/7/os/x86_64/"
read REPOURL
export REPOURL=$REPOURL
echo

echo "Create rpm repo named: $REPONAME using URL: $REPOURL ? (y/n)"
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

# Creating a new repository
export REPO_HREF=$(http POST $BASE_ADDR/pulp/api/v3/repositories/rpm/rpm/ name=$REPONAME | jq -r '.pulp_href')

# Inspecting Repository
http $BASE_ADDR$REPO_HREF

# Create new RPM remote
http POST $BASE_ADDR/pulp/api/v3/remotes/rpm/rpm/ name="$REPONAME" url="$REPOURL" policy='on_demand'

# Export an environment variable for the new remote URI
export REMOTE_HREF=$(http $BASE_ADDR/pulp/api/v3/remotes/rpm/rpm/ | jq -r '.results[] | select(.name == env.REPONAME) | .pulp_href')

# Inspecting new Remote
http $BASE_ADDR$REMOTE_HREF

# Sync repository 
export TASK_URL=$(http POST $BASE_ADDR$REPO_HREF'sync/' remote=$REMOTE_HREF | jq -r '.task')

# Poll the task (here we use a function defined in docs/_scripts/base.sh)
wait_until_task_finished $BASE_ADDR$TASK_URL

# After the task is complete, it gives us a new repository version
export REPOVERSION_HREF=$(http $BASE_ADDR$TASK_URL| jq -r '.created_resources | first')

# Inspecting RepositoryVersion
http $BASE_ADDR$REPOVERSION_HREF

# Create RPM publication
export TASK_URL=$(http POST $BASE_ADDR/pulp/api/v3/publications/rpm/rpm/ repository=$REPO_HREF metadata_checksum_type=sha256 | jq -r '.task')

# Poll the task (here we use a function defined in docs/_scripts/base.sh)
wait_until_task_finished $BASE_ADDR$TASK_URL
echo

# After the task is complete, it gives us a new publication
export PUBLICATION_HREF=$(http $BASE_ADDR$TASK_URL| jq -r '.created_resources | first')

# Inspecting Publication
http $BASE_ADDR$PUBLICATION_HREF

# Create RPM distribution for publication
export TASK_URL=$(http POST $BASE_ADDR/pulp/api/v3/distributions/rpm/rpm/ publication=$PUBLICATION_HREF name="$REPONAME" base_path="$REPONAME" | jq -r '.task')

# Poll the task (here we use a function defined in docs/_scripts/base.sh)
wait_until_task_finished $BASE_ADDR$TASK_URL

# After the task is complete, it gives us a new distribution
export DISTRIBUTION_HREF=$(http $BASE_ADDR$TASK_URL| jq -r '.created_resources | first')

#Inspecting Distribution
http $BASE_ADDR$DISTRIBUTION_HREF

exit
