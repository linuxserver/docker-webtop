pipeline {
  agent {
    label 'X86-64-MULTI'
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '60'))
    parallelsAlwaysFailFast()
  }
  // Input to determine if this is a package check
  parameters {
    string(defaultValue: 'false', description: 'package check run', name: 'PACKAGE_CHECK')
  }
  // Configuration for the variables used for this specific repo
  environment {
    BUILDS_DISCORD=credentials('build_webhook_url')
    GITHUB_TOKEN=credentials('498b4638-2d02-4ce5-832d-8a57d01d97ab')
    GITLAB_TOKEN=credentials('b6f0f1dd-6952-4cf6-95d1-9c06380283f0')
    GITLAB_NAMESPACE=credentials('gitlab-namespace-id')
    DOCKERHUB_TOKEN=credentials('docker-hub-ci-pat')
    QUAYIO_API_TOKEN=credentials('quayio-repo-api-token')
    GIT_SIGNING_KEY=credentials('484fbca6-9a4f-455e-b9e3-97ac98785f5f')
    BUILD_VERSION_ARG = 'OS_VERSION'
    LS_USER = 'linuxserver'
    LS_REPO = 'docker-webtop'
    CONTAINER_NAME = 'webtop'
    DOCKERHUB_IMAGE = 'linuxserver/webtop'
    DEV_DOCKERHUB_IMAGE = 'lsiodev/webtop'
    PR_DOCKERHUB_IMAGE = 'lspipepr/webtop'
    DIST_IMAGE = 'ubuntu'
    MULTIARCH='true'
    CI='true'
    CI_WEB='true'
    CI_PORT='3000'
    CI_SSL='false'
    CI_DELAY='120'
    CI_DOCKERENV='TZ=US/Pacific'
    CI_AUTH='user:password'
    CI_WEBPATH=''
  }
  stages {
    stage("Set git config"){
      steps{
        sh '''#!/bin/bash
              cat ${GIT_SIGNING_KEY} > /config/.ssh/id_sign
              chmod 600 /config/.ssh/id_sign
              ssh-keygen -y -f /config/.ssh/id_sign > /config/.ssh/id_sign.pub
              echo "Using $(ssh-keygen -lf /config/.ssh/id_sign) to sign commits"
              git config --global gpg.format ssh
              git config --global user.signingkey /config/.ssh/id_sign
              git config --global commit.gpgsign true
        '''
      }
    }
    // Setup all the basic environment variables needed for the build
    stage("Set ENV Variables base"){
      steps{
        echo "Running on node: ${NODE_NAME}"
        sh '''#! /bin/bash
              containers=$(docker ps -aq)
              if [[ -n "${containers}" ]]; then
                docker stop ${containers}
              fi
              docker system prune -af --volumes || : '''
        script{
          env.EXIT_STATUS = ''
          env.LS_RELEASE = sh(
            script: '''docker run --rm quay.io/skopeo/stable:v1 inspect docker://ghcr.io/${LS_USER}/${CONTAINER_NAME}:ubuntu-mate 2>/dev/null | jq -r '.Labels.build_version' | awk '{print $3}' | grep '\\-ls' || : ''',
            returnStdout: true).trim()
          env.LS_RELEASE_NOTES = sh(
            script: '''cat readme-vars.yml | awk -F \\" '/date: "[0-9][0-9].[0-9][0-9].[0-9][0-9]:/ {print $4;exit;}' | sed -E ':a;N;$!ba;s/\\r{0,1}\\n/\\\\n/g' ''',
            returnStdout: true).trim()
          env.GITHUB_DATE = sh(
            script: '''date '+%Y-%m-%dT%H:%M:%S%:z' ''',
            returnStdout: true).trim()
          env.COMMIT_SHA = sh(
            script: '''git rev-parse HEAD''',
            returnStdout: true).trim()
          env.GH_DEFAULT_BRANCH = sh(
            script: '''git remote show origin | grep "HEAD branch:" | sed 's|.*HEAD branch: ||' ''',
            returnStdout: true).trim()
          env.CODE_URL = 'https://github.com/' + env.LS_USER + '/' + env.LS_REPO + '/commit/' + env.GIT_COMMIT
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.DOCKERHUB_IMAGE + '/tags/'
          env.PULL_REQUEST = env.CHANGE_ID
          env.TEMPLATED_FILES = 'Jenkinsfile README.md LICENSE .editorconfig ./.github/CONTRIBUTING.md ./.github/FUNDING.yml ./.github/ISSUE_TEMPLATE/config.yml ./.github/ISSUE_TEMPLATE/issue.bug.yml ./.github/ISSUE_TEMPLATE/issue.feature.yml ./.github/PULL_REQUEST_TEMPLATE.md ./.github/workflows/external_trigger_scheduler.yml ./.github/workflows/greetings.yml ./.github/workflows/package_trigger_scheduler.yml ./.github/workflows/call_issue_pr_tracker.yml ./.github/workflows/call_issues_cron.yml ./.github/workflows/permissions.yml ./.github/workflows/external_trigger.yml'
        }
        sh '''#! /bin/bash
              echo "The default github branch detected as ${GH_DEFAULT_BRANCH}" '''
        script{
          env.LS_RELEASE_NUMBER = sh(
            script: '''echo ${LS_RELEASE} |sed 's/^.*-ls//g' ''',
            returnStdout: true).trim()
        }
        script{
          env.LS_TAG_NUMBER = sh(
            script: '''#! /bin/bash
                       tagsha=$(git rev-list -n 1 ubuntu-mate-${LS_RELEASE} 2>/dev/null)
                       if [ "${tagsha}" == "${COMMIT_SHA}" ]; then
                         echo ${LS_RELEASE_NUMBER}
                       elif [ -z "${GIT_COMMIT}" ]; then
                         echo ${LS_RELEASE_NUMBER}
                       else
                         echo $((${LS_RELEASE_NUMBER} + 1))
                       fi''',
            returnStdout: true).trim()
        }
      }
    }
    /* #######################
       Package Version Tagging
       ####################### */
    // Grab the current package versions in Git to determine package tag
    stage("Set Package tag"){
      steps{
        script{
          env.PACKAGE_TAG = sh(
            script: '''#!/bin/bash
                       if [ -e package_versions.txt ] ; then
                         cat package_versions.txt | md5sum | cut -c1-8
                       else
                         echo none
                       fi''',
            returnStdout: true).trim()
        }
      }
    }
    /* ########################
       External Release Tagging
       ######################## */
    // If this is an os release set release type to none to indicate no external release
    stage("Set ENV os"){
      steps{
        script{
          env.EXT_RELEASE = env.PACKAGE_TAG
          env.RELEASE_LINK = 'none'
        }
      }
    }
    // Sanitize the release tag and strip illegal docker or github characters
    stage("Sanitize tag"){
      steps{
        script{
          env.EXT_RELEASE_CLEAN = sh(
            script: '''echo ${EXT_RELEASE} | sed 's/[~,%@+;:/ ]//g' ''',
            returnStdout: true).trim()

          def semver = env.EXT_RELEASE_CLEAN =~ /(\d+)\.(\d+)\.(\d+)/
          if (semver.find()) {
            env.SEMVER = "${semver[0][1]}.${semver[0][2]}.${semver[0][3]}"
          } else {
            semver = env.EXT_RELEASE_CLEAN =~ /(\d+)\.(\d+)(?:\.(\d+))?(.*)/
            if (semver.find()) {
              if (semver[0][3]) {
                env.SEMVER = "${semver[0][1]}.${semver[0][2]}.${semver[0][3]}"
              } else if (!semver[0][3] && !semver[0][4]) {
                env.SEMVER = "${semver[0][1]}.${semver[0][2]}.${(new Date()).format('YYYYMMdd')}"
              }
            }
          }

          if (env.SEMVER != null) {
            if (BRANCH_NAME != "${env.GH_DEFAULT_BRANCH}") {
              env.SEMVER = "${env.SEMVER}-${BRANCH_NAME}"
            }
            println("SEMVER: ${env.SEMVER}")
          } else {
            println("No SEMVER detected")
          }

        }
      }
    }
    // If this is a ubuntu-mate build use live docker endpoints
    stage("Set ENV live build"){
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
      }
      steps {
        script{
          env.IMAGE = env.DOCKERHUB_IMAGE
          env.GITHUBIMAGE = 'ghcr.io/' + env.LS_USER + '/' + env.CONTAINER_NAME
          env.GITLABIMAGE = 'registry.gitlab.com/linuxserver.io/' + env.LS_REPO + '/' + env.CONTAINER_NAME
          env.QUAYIMAGE = 'quay.io/linuxserver.io/' + env.CONTAINER_NAME
          if (env.MULTIARCH == 'true') {
            env.CI_TAGS = 'amd64-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER + '|arm64v8-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          } else {
            env.CI_TAGS = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          env.META_TAG = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          env.EXT_RELEASE_TAG = 'ubuntu-mate-version-' + env.EXT_RELEASE_CLEAN
          env.BUILDCACHE = 'docker.io/lsiodev/buildcache,registry.gitlab.com/linuxserver.io/docker-jenkins-builder/lsiodev-buildcache,ghcr.io/linuxserver/lsiodev-buildcache,quay.io/linuxserver.io/lsiodev-buildcache'
        }
      }
    }
    // If this is a dev build use dev docker endpoints
    stage("Set ENV dev build"){
      when {
        not {branch "ubuntu-mate"}
        environment name: 'CHANGE_ID', value: ''
      }
      steps {
        script{
          env.IMAGE = env.DEV_DOCKERHUB_IMAGE
          env.GITHUBIMAGE = 'ghcr.io/' + env.LS_USER + '/lsiodev-' + env.CONTAINER_NAME
          env.GITLABIMAGE = 'registry.gitlab.com/linuxserver.io/' + env.LS_REPO + '/lsiodev-' + env.CONTAINER_NAME
          env.QUAYIMAGE = 'quay.io/linuxserver.io/lsiodev-' + env.CONTAINER_NAME
          if (env.MULTIARCH == 'true') {
            env.CI_TAGS = 'amd64-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '|arm64v8-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          } else {
            env.CI_TAGS = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          env.META_TAG = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          env.EXT_RELEASE_TAG = 'ubuntu-mate-version-' + env.EXT_RELEASE_CLEAN
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.DEV_DOCKERHUB_IMAGE + '/tags/'
          env.BUILDCACHE = 'docker.io/lsiodev/buildcache,registry.gitlab.com/linuxserver.io/docker-jenkins-builder/lsiodev-buildcache,ghcr.io/linuxserver/lsiodev-buildcache,quay.io/linuxserver.io/lsiodev-buildcache'
        }
      }
    }
    // If this is a pull request build use dev docker endpoints
    stage("Set ENV PR build"){
      when {
        not {environment name: 'CHANGE_ID', value: ''}
      }
      steps {
        script{
          env.IMAGE = env.PR_DOCKERHUB_IMAGE
          env.GITHUBIMAGE = 'ghcr.io/' + env.LS_USER + '/lspipepr-' + env.CONTAINER_NAME
          env.GITLABIMAGE = 'registry.gitlab.com/linuxserver.io/' + env.LS_REPO + '/lspipepr-' + env.CONTAINER_NAME
          env.QUAYIMAGE = 'quay.io/linuxserver.io/lspipepr-' + env.CONTAINER_NAME
          if (env.MULTIARCH == 'true') {
            env.CI_TAGS = 'amd64-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST + '|arm64v8-ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          } else {
            env.CI_TAGS = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          env.META_TAG = 'ubuntu-mate-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          env.EXT_RELEASE_TAG = 'ubuntu-mate-version-' + env.EXT_RELEASE_CLEAN
          env.CODE_URL = 'https://github.com/' + env.LS_USER + '/' + env.LS_REPO + '/pull/' + env.PULL_REQUEST
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.PR_DOCKERHUB_IMAGE + '/tags/'
          env.BUILDCACHE = 'docker.io/lsiodev/buildcache,registry.gitlab.com/linuxserver.io/docker-jenkins-builder/lsiodev-buildcache,ghcr.io/linuxserver/lsiodev-buildcache,quay.io/linuxserver.io/lsiodev-buildcache'
        }
      }
    }
    // Run ShellCheck
    stage('ShellCheck') {
      when {
        environment name: 'CI', value: 'true'
      }
      steps {
        withCredentials([
          string(credentialsId: 'ci-tests-s3-key-id', variable: 'S3_KEY'),
          string(credentialsId: 'ci-tests-s3-secret-access-key', variable: 'S3_SECRET')
        ]) {
          script{
            env.SHELLCHECK_URL = 'https://ci-tests.linuxserver.io/' + env.IMAGE + '/' + env.META_TAG + '/shellcheck-result.xml'
          }
          sh '''curl -sL https://raw.githubusercontent.com/linuxserver/docker-jenkins-builder/master/checkrun.sh | /bin/bash'''
          sh '''#! /bin/bash
                docker run --rm \
                  -v ${WORKSPACE}:/mnt \
                  -e AWS_ACCESS_KEY_ID=\"${S3_KEY}\" \
                  -e AWS_SECRET_ACCESS_KEY=\"${S3_SECRET}\" \
                  ghcr.io/linuxserver/baseimage-alpine:3.20 s6-envdir -fn -- /var/run/s6/container_environment /bin/bash -c "\
                    apk add --no-cache python3 && \
                    python3 -m venv /lsiopy && \
                    pip install --no-cache-dir -U pip && \
                    pip install --no-cache-dir s3cmd && \
                    s3cmd put --no-preserve --acl-public -m text/xml /mnt/shellcheck-result.xml s3://ci-tests.linuxserver.io/${IMAGE}/${META_TAG}/shellcheck-result.xml" || :'''
        }
      }
    }
    // Use helper containers to render templated files
    stage('Update-Templates') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        expression {
          env.CONTAINER_NAME != null
        }
      }
      steps {
        sh '''#! /bin/bash
              set -e
              TEMPDIR=$(mktemp -d)
              docker pull ghcr.io/linuxserver/jenkins-builder:latest
              # Cloned repo paths for templating:
              # ${TEMPDIR}/docker-${CONTAINER_NAME}: Cloned branch ubuntu-mate of ${LS_USER}/${LS_REPO} for running the jenkins builder on
              # ${TEMPDIR}/repo/${LS_REPO}: Cloned branch ubuntu-mate of ${LS_USER}/${LS_REPO} for commiting various templated file changes and pushing back to Github
              # ${TEMPDIR}/docs/docker-documentation: Cloned docs repo for pushing docs updates to Github
              # ${TEMPDIR}/unraid/docker-templates: Cloned docker-templates repo to check for logos
              # ${TEMPDIR}/unraid/templates: Cloned templates repo for commiting unraid template changes and pushing back to Github
              git clone --branch ubuntu-mate --depth 1 https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/docker-${CONTAINER_NAME}
              docker run --rm -v ${TEMPDIR}/docker-${CONTAINER_NAME}:/tmp -e LOCAL=true -e PUID=$(id -u) -e PGID=$(id -g) ghcr.io/linuxserver/jenkins-builder:latest 
              echo "Starting Stage 1 - Jenkinsfile update"
              if [[ "$(md5sum Jenkinsfile | awk '{ print $1 }')" != "$(md5sum ${TEMPDIR}/docker-${CONTAINER_NAME}/Jenkinsfile | awk '{ print $1 }')" ]]; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f ubuntu-mate
                cp ${TEMPDIR}/docker-${CONTAINER_NAME}/Jenkinsfile ${TEMPDIR}/repo/${LS_REPO}/
                git add Jenkinsfile
                git commit -m 'Bot Updating Templated Files'
                git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Updating Jenkinsfile and exiting build, new one will trigger based on commit"
                rm -Rf ${TEMPDIR}
                exit 0
              else
                echo "Jenkinsfile is up to date."
              fi
              echo "Starting Stage 2 - Delete old templates"
              OLD_TEMPLATES=".github/ISSUE_TEMPLATE.md .github/ISSUE_TEMPLATE/issue.bug.md .github/ISSUE_TEMPLATE/issue.feature.md .github/workflows/call_invalid_helper.yml .github/workflows/stale.yml .github/workflows/package_trigger.yml"
              for i in ${OLD_TEMPLATES}; do
                if [[ -f "${i}" ]]; then
                  TEMPLATES_TO_DELETE="${i} ${TEMPLATES_TO_DELETE}"
                fi
              done
              if [[ -n "${TEMPLATES_TO_DELETE}" ]]; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f ubuntu-mate
                for i in ${TEMPLATES_TO_DELETE}; do
                  git rm "${i}"
                done
                git commit -m 'Bot Updating Templated Files'
                git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Deleting old/deprecated templates and exiting build, new one will trigger based on commit"
                rm -Rf ${TEMPDIR}
                exit 0
              else
                echo "No templates to delete"
              fi
              echo "Starting Stage 3 - Update templates"
              CURRENTHASH=$(grep -hs ^ ${TEMPLATED_FILES} | md5sum | cut -c1-8)
              cd ${TEMPDIR}/docker-${CONTAINER_NAME}
              NEWHASH=$(grep -hs ^ ${TEMPLATED_FILES} | md5sum | cut -c1-8)
              if [[ "${CURRENTHASH}" != "${NEWHASH}" ]] || ! grep -q '.jenkins-external' "${WORKSPACE}/.gitignore" 2>/dev/null; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f ubuntu-mate
                cd ${TEMPDIR}/docker-${CONTAINER_NAME}
                mkdir -p ${TEMPDIR}/repo/${LS_REPO}/.github/workflows
                mkdir -p ${TEMPDIR}/repo/${LS_REPO}/.github/ISSUE_TEMPLATE
                cp --parents ${TEMPLATED_FILES} ${TEMPDIR}/repo/${LS_REPO}/ || :
                cp --parents readme-vars.yml ${TEMPDIR}/repo/${LS_REPO}/ || :
                cd ${TEMPDIR}/repo/${LS_REPO}/
                if ! grep -q '.jenkins-external' .gitignore 2>/dev/null; then
                  echo ".jenkins-external" >> .gitignore
                  git add .gitignore
                fi
                git add readme-vars.yml ${TEMPLATED_FILES}
                git commit -m 'Bot Updating Templated Files'
                git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Updating templates and exiting build, new one will trigger based on commit"
                rm -Rf ${TEMPDIR}
                exit 0
              else
                echo "false" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "No templates to update"
              fi
              echo "Starting Stage 4 - External repo updates: Docs, Unraid Template and Readme Sync to Docker Hub"
              mkdir -p ${TEMPDIR}/docs
              git clone --depth=1 https://github.com/linuxserver/docker-documentation.git ${TEMPDIR}/docs/docker-documentation
              if [[ "${BRANCH_NAME}" == "${GH_DEFAULT_BRANCH}"  ]] && [[ (! -f ${TEMPDIR}/docs/docker-documentation/docs/images/docker-${CONTAINER_NAME}.md) || ("$(md5sum ${TEMPDIR}/docs/docker-documentation/docs/images/docker-${CONTAINER_NAME}.md | awk '{ print $1 }')" != "$(md5sum ${TEMPDIR}/docker-${CONTAINER_NAME}/.jenkins-external/docker-${CONTAINER_NAME}.md | awk '{ print $1 }')") ]]; then
                cp ${TEMPDIR}/docker-${CONTAINER_NAME}/.jenkins-external/docker-${CONTAINER_NAME}.md ${TEMPDIR}/docs/docker-documentation/docs/images/
                cd ${TEMPDIR}/docs/docker-documentation
                GH_DOCS_DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch:" | sed 's|.*HEAD branch: ||')
                git add docs/images/docker-${CONTAINER_NAME}.md
                echo "Updating docs repo"
                git commit -m 'Bot Updating Documentation'
                git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/linuxserver/docker-documentation.git ${GH_DOCS_DEFAULT_BRANCH} --rebase
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/linuxserver/docker-documentation.git ${GH_DOCS_DEFAULT_BRANCH} || \
                  (MAXWAIT="10" && echo "Push to docs failed, trying again in ${MAXWAIT} seconds" && \
                  sleep $((RANDOM % MAXWAIT)) && \
                  git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/linuxserver/docker-documentation.git ${GH_DOCS_DEFAULT_BRANCH} --rebase && \
                  git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/linuxserver/docker-documentation.git ${GH_DOCS_DEFAULT_BRANCH})
              else
                echo "Docs update not needed, skipping"
              fi
              if [[ "${BRANCH_NAME}" == "${GH_DEFAULT_BRANCH}" ]]; then
                if [[ $(cat ${TEMPDIR}/docker-${CONTAINER_NAME}/README.md | wc -m) -gt 25000 ]]; then
                  echo "Readme is longer than 25,000 characters. Syncing the lite version to Docker Hub"
                  DH_README_SYNC_PATH="${TEMPDIR}/docker-${CONTAINER_NAME}/.jenkins-external/README.lite"
                else
                  echo "Syncing readme to Docker Hub"
                  DH_README_SYNC_PATH="${TEMPDIR}/docker-${CONTAINER_NAME}/README.md"
                fi
                if curl -s https://hub.docker.com/v2/namespaces/${DOCKERHUB_IMAGE%%/*}/repositories/${DOCKERHUB_IMAGE##*/}/tags | jq -r '.message' | grep -q 404; then
                  echo "Docker Hub endpoint doesn't exist. Creating endpoint first."
                  DH_TOKEN=$(curl -d '{"username":"linuxserverci", "password":"'${DOCKERHUB_TOKEN}'"}' -H "Content-Type: application/json" -X POST https://hub.docker.com/v2/users/login | jq -r '.token')
                  curl -s \
                    -H "Authorization: JWT ${DH_TOKEN}" \
                    -H "Content-Type: application/json" \
                    -X POST \
                    -d '{"name":"'${DOCKERHUB_IMAGE##*/}'", "namespace":"'${DOCKERHUB_IMAGE%%/*}'"}' \
                    https://hub.docker.com/v2/repositories/ || :
                fi
                DH_TOKEN=$(curl -d '{"username":"linuxserverci", "password":"'${DOCKERHUB_TOKEN}'"}' -H "Content-Type: application/json" -X POST https://hub.docker.com/v2/users/login | jq -r '.token')
                curl -s \
                  -H "Authorization: JWT ${DH_TOKEN}" \
                  -H "Content-Type: application/json" \
                  -X PATCH \
                  -d "{\\"full_description\\":$(jq -Rsa . ${DH_README_SYNC_PATH})}" \
                  https://hub.docker.com/v2/repositories/${DOCKERHUB_IMAGE} || :
              else
                echo "Not the default Github branch. Skipping readme sync to Docker Hub."
              fi
              rm -Rf ${TEMPDIR}'''
        script{
          env.FILES_UPDATED = sh(
            script: '''cat /tmp/${COMMIT_SHA}-${BUILD_NUMBER}''',
            returnStdout: true).trim()
        }
      }
    }
    // Exit the build if the Templated files were just updated
    stage('Template-exit') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'FILES_UPDATED', value: 'true'
        expression {
          env.CONTAINER_NAME != null
        }
      }
      steps {
        script{
          env.EXIT_STATUS = 'ABORTED'
        }
      }
    }
    // If this is a ubuntu-mate build check the S6 service file perms
    stage("Check S6 Service file Permissions"){
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        script{
          sh '''#! /bin/bash
            WRONG_PERM=$(find ./  -path "./.git" -prune -o \\( -name "run" -o -name "finish" -o -name "check" \\) -not -perm -u=x,g=x,o=x -print)
            if [[ -n "${WRONG_PERM}" ]]; then
              echo "The following S6 service files are missing the executable bit; canceling the faulty build: ${WRONG_PERM}"
              exit 1
            else
              echo "S6 service file perms look good."
            fi '''
        }
      }
    }
    /* #######################
       GitLab Mirroring and Quay.io Repo Visibility
       ####################### */
    // Ping into Gitlab to mirror this repo and have a registry endpoint & mark this repo on Quay.io as public
    stage("GitLab Mirror and Quay.io Visibility"){
      when {
        environment name: 'EXIT_STATUS', value: ''
      }
      steps{
        sh '''curl -H "Content-Type: application/json" -H "Private-Token: ${GITLAB_TOKEN}" -X POST https://gitlab.com/api/v4/projects \
          -d '{"namespace_id":'${GITLAB_NAMESPACE}',\
            "name":"'${LS_REPO}'",
            "mirror":true,\
            "import_url":"https://github.com/linuxserver/'${LS_REPO}'.git",\
            "issues_access_level":"disabled",\
            "merge_requests_access_level":"disabled",\
            "repository_access_level":"enabled",\
            "visibility":"public"}' '''
        sh '''curl -H "Private-Token: ${GITLAB_TOKEN}" -X PUT "https://gitlab.com/api/v4/projects/Linuxserver.io%2F${LS_REPO}" \
          -d "mirror=true&import_url=https://github.com/linuxserver/${LS_REPO}.git" '''
        sh '''curl -H "Content-Type: application/json" -H "Authorization: Bearer ${QUAYIO_API_TOKEN}" -X POST "https://quay.io/api/v1/repository${QUAYIMAGE/quay.io/}/changevisibility" \
          -d '{"visibility":"public"}' ||: '''
      } 
    }
    /* ###############
       Build Container
       ############### */
    // Build Docker container for push to LS Repo
    stage('Build-Single') {
      when {
        expression {
          env.MULTIARCH == 'false' || params.PACKAGE_CHECK == 'true'
        }
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        echo "Running on node: ${NODE_NAME}"
        sh "sed -r -i 's|(^FROM .*)|\\1\\n\\nENV LSIO_FIRST_PARTY=true|g' Dockerfile"
        sh "docker buildx build \
          --label \"org.opencontainers.image.created=${GITHUB_DATE}\" \
          --label \"org.opencontainers.image.authors=linuxserver.io\" \
          --label \"org.opencontainers.image.url=https://github.com/linuxserver/docker-webtop/packages\" \
          --label \"org.opencontainers.image.documentation=https://docs.linuxserver.io/images/docker-webtop\" \
          --label \"org.opencontainers.image.source=https://github.com/linuxserver/docker-webtop\" \
          --label \"org.opencontainers.image.version=${EXT_RELEASE_CLEAN}-ls${LS_TAG_NUMBER}\" \
          --label \"org.opencontainers.image.revision=${COMMIT_SHA}\" \
          --label \"org.opencontainers.image.vendor=linuxserver.io\" \
          --label \"org.opencontainers.image.licenses=GPL-3.0-only\" \
          --label \"org.opencontainers.image.ref.name=${COMMIT_SHA}\" \
          --label \"org.opencontainers.image.title=Webtop\" \
          --label \"org.opencontainers.image.description=webtop image by linuxserver.io\" \
          --no-cache --pull -t ${IMAGE}:${META_TAG} --platform=linux/amd64 \
          --provenance=true --sbom=true --builder=container --load \
          --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
        sh '''#! /bin/bash
              set -e
              IFS=',' read -ra CACHE <<< "$BUILDCACHE"
              for i in "${CACHE[@]}"; do
                docker tag ${IMAGE}:${META_TAG} ${i}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
              done
           '''
        withCredentials([
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: 'Quay.io-Robot',
            usernameVariable: 'QUAYUSER',
            passwordVariable: 'QUAYPASS'
          ]
        ]) {
          retry_backoff(5,5) {
              sh '''#! /bin/bash
                    set -e
                    echo $DOCKERHUB_TOKEN | docker login -u linuxserverci --password-stdin
                    echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
                    echo $GITLAB_TOKEN | docker login registry.gitlab.com -u LinuxServer.io --password-stdin
                    echo $QUAYPASS | docker login quay.io -u $QUAYUSER --password-stdin
                    if [[ "${PACKAGE_CHECK}" != "true" ]]; then
                      IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                      for i in "${CACHE[@]}"; do
                        docker push ${i}:amd64-${COMMIT_SHA}-${BUILD_NUMBER} &
                      done
                      for p in $(jobs -p); do
                        wait "$p" || { echo "job $p failed" >&2; exit 1; }
                      done
                    fi
                '''
          }
        }
      }
    }
    // Build MultiArch Docker containers for push to LS Repo
    stage('Build-Multi') {
      when {
        allOf {
          environment name: 'MULTIARCH', value: 'true'
          expression { params.PACKAGE_CHECK == 'false' }
        }
        environment name: 'EXIT_STATUS', value: ''
      }
      parallel {
        stage('Build X86') {
          steps {
            echo "Running on node: ${NODE_NAME}"
            sh "sed -r -i 's|(^FROM .*)|\\1\\n\\nENV LSIO_FIRST_PARTY=true|g' Dockerfile"
            sh "docker buildx build \
              --label \"org.opencontainers.image.created=${GITHUB_DATE}\" \
              --label \"org.opencontainers.image.authors=linuxserver.io\" \
              --label \"org.opencontainers.image.url=https://github.com/linuxserver/docker-webtop/packages\" \
              --label \"org.opencontainers.image.documentation=https://docs.linuxserver.io/images/docker-webtop\" \
              --label \"org.opencontainers.image.source=https://github.com/linuxserver/docker-webtop\" \
              --label \"org.opencontainers.image.version=${EXT_RELEASE_CLEAN}-ls${LS_TAG_NUMBER}\" \
              --label \"org.opencontainers.image.revision=${COMMIT_SHA}\" \
              --label \"org.opencontainers.image.vendor=linuxserver.io\" \
              --label \"org.opencontainers.image.licenses=GPL-3.0-only\" \
              --label \"org.opencontainers.image.ref.name=${COMMIT_SHA}\" \
              --label \"org.opencontainers.image.title=Webtop\" \
              --label \"org.opencontainers.image.description=webtop image by linuxserver.io\" \
              --no-cache --pull -t ${IMAGE}:amd64-${META_TAG} --platform=linux/amd64 \
              --provenance=true --sbom=true --builder=container --load \
              --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
            sh '''#! /bin/bash
                  set -e
                  IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                  for i in "${CACHE[@]}"; do
                    docker tag ${IMAGE}:amd64-${META_TAG} ${i}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
                  done
               '''
            withCredentials([
              [
                $class: 'UsernamePasswordMultiBinding',
                credentialsId: 'Quay.io-Robot',
                usernameVariable: 'QUAYUSER',
                passwordVariable: 'QUAYPASS'
              ]
            ]) {
              retry_backoff(5,5) {
                  sh '''#! /bin/bash
                        set -e
                        echo $DOCKERHUB_TOKEN | docker login -u linuxserverci --password-stdin
                        echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
                        echo $GITLAB_TOKEN | docker login registry.gitlab.com -u LinuxServer.io --password-stdin
                        echo $QUAYPASS | docker login quay.io -u $QUAYUSER --password-stdin
                        if [[ "${PACKAGE_CHECK}" != "true" ]]; then
                          IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                          for i in "${CACHE[@]}"; do
                            docker push ${i}:amd64-${COMMIT_SHA}-${BUILD_NUMBER} &
                          done
                          for p in $(jobs -p); do
                            wait "$p" || { echo "job $p failed" >&2; exit 1; }
                          done
                        fi
                    '''
              }
            }
          }
        }
        stage('Build ARM64') {
          agent {
            label 'ARM64'
          }
          steps {
            echo "Running on node: ${NODE_NAME}"
            sh "sed -r -i 's|(^FROM .*)|\\1\\n\\nENV LSIO_FIRST_PARTY=true|g' Dockerfile.aarch64"
            sh "docker buildx build \
              --label \"org.opencontainers.image.created=${GITHUB_DATE}\" \
              --label \"org.opencontainers.image.authors=linuxserver.io\" \
              --label \"org.opencontainers.image.url=https://github.com/linuxserver/docker-webtop/packages\" \
              --label \"org.opencontainers.image.documentation=https://docs.linuxserver.io/images/docker-webtop\" \
              --label \"org.opencontainers.image.source=https://github.com/linuxserver/docker-webtop\" \
              --label \"org.opencontainers.image.version=${EXT_RELEASE_CLEAN}-ls${LS_TAG_NUMBER}\" \
              --label \"org.opencontainers.image.revision=${COMMIT_SHA}\" \
              --label \"org.opencontainers.image.vendor=linuxserver.io\" \
              --label \"org.opencontainers.image.licenses=GPL-3.0-only\" \
              --label \"org.opencontainers.image.ref.name=${COMMIT_SHA}\" \
              --label \"org.opencontainers.image.title=Webtop\" \
              --label \"org.opencontainers.image.description=webtop image by linuxserver.io\" \
              --no-cache --pull -f Dockerfile.aarch64 -t ${IMAGE}:arm64v8-${META_TAG} --platform=linux/arm64 \
              --provenance=true --sbom=true --builder=container --load \
              --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
            sh '''#! /bin/bash
                  set -e
                  IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                  for i in "${CACHE[@]}"; do
                    docker tag ${IMAGE}:arm64v8-${META_TAG} ${i}:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}
                  done
               '''
            withCredentials([
              [
                $class: 'UsernamePasswordMultiBinding',
                credentialsId: 'Quay.io-Robot',
                usernameVariable: 'QUAYUSER',
                passwordVariable: 'QUAYPASS'
              ]
            ]) {
              retry_backoff(5,5) {
                  sh '''#! /bin/bash
                        set -e
                        echo $DOCKERHUB_TOKEN | docker login -u linuxserverci --password-stdin
                        echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
                        echo $GITLAB_TOKEN | docker login registry.gitlab.com -u LinuxServer.io --password-stdin
                        echo $QUAYPASS | docker login quay.io -u $QUAYUSER --password-stdin
                        if [[ "${PACKAGE_CHECK}" != "true" ]]; then
                          IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                          for i in "${CACHE[@]}"; do
                            docker push ${i}:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER} &
                          done
                          for p in $(jobs -p); do
                            wait "$p" || { echo "job $p failed" >&2; exit 1; }
                          done
                        fi
                    '''
              }
            }
            sh '''#! /bin/bash
                  containers=$(docker ps -aq)
                  if [[ -n "${containers}" ]]; then
                    docker stop ${containers}
                  fi
                  docker system prune -af --volumes || :
               '''
          }
        }
      }
    }
    // Take the image we just built and dump package versions for comparison
    stage('Update-packages') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        sh '''#! /bin/bash
              set -e
              TEMPDIR=$(mktemp -d)
              if [ "${MULTIARCH}" == "true" ] && [ "${PACKAGE_CHECK}" != "true" ]; then
                LOCAL_CONTAINER=${IMAGE}:amd64-${META_TAG}
              else
                LOCAL_CONTAINER=${IMAGE}:${META_TAG}
              fi
              touch ${TEMPDIR}/package_versions.txt
              docker run --rm \
                -v /var/run/docker.sock:/var/run/docker.sock:ro \
                -v ${TEMPDIR}:/tmp \
                ghcr.io/anchore/syft:latest \
                ${LOCAL_CONTAINER} -o table=/tmp/package_versions.txt
              NEW_PACKAGE_TAG=$(md5sum ${TEMPDIR}/package_versions.txt | cut -c1-8 )
              echo "Package tag sha from current packages in buit container is ${NEW_PACKAGE_TAG} comparing to old ${PACKAGE_TAG} from github"
              if [ "${NEW_PACKAGE_TAG}" != "${PACKAGE_TAG}" ]; then
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/${LS_REPO}
                git --git-dir ${TEMPDIR}/${LS_REPO}/.git checkout -f ubuntu-mate
                cp ${TEMPDIR}/package_versions.txt ${TEMPDIR}/${LS_REPO}/
                cd ${TEMPDIR}/${LS_REPO}/
                wait
                git add package_versions.txt
                git commit -m 'Bot Updating Package Versions'
                git pull https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git ubuntu-mate
                echo "true" > /tmp/packages-${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Package tag updated, stopping build process"
              else
                echo "false" > /tmp/packages-${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Package tag is same as previous continue with build process"
              fi
              rm -Rf ${TEMPDIR}'''
        script{
          env.PACKAGE_UPDATED = sh(
            script: '''cat /tmp/packages-${COMMIT_SHA}-${BUILD_NUMBER}''',
            returnStdout: true).trim()
        }
      }
    }
    // Exit the build if the package file was just updated
    stage('PACKAGE-exit') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'PACKAGE_UPDATED', value: 'true'
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        script{
          env.EXIT_STATUS = 'ABORTED'
        }
      }
    }
    // Exit the build if this is just a package check and there are no changes to push
    stage('PACKAGECHECK-exit') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'PACKAGE_UPDATED', value: 'false'
        environment name: 'EXIT_STATUS', value: ''
        expression {
          params.PACKAGE_CHECK == 'true'
        }
      }
      steps {
        script{
          env.EXIT_STATUS = 'ABORTED'
        }
      }
    }
    /* #######
       Testing
       ####### */
    // Run Container tests
    stage('Test') {
      when {
        environment name: 'CI', value: 'true'
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        withCredentials([
          string(credentialsId: 'ci-tests-s3-key-id', variable: 'S3_KEY'),
          string(credentialsId: 'ci-tests-s3-secret-access-key	', variable: 'S3_SECRET')
        ]) {
          script{
            env.CI_URL = 'https://ci-tests.linuxserver.io/' + env.IMAGE + '/' + env.META_TAG + '/index.html'
            env.CI_JSON_URL = 'https://ci-tests.linuxserver.io/' + env.IMAGE + '/' + env.META_TAG + '/report.json'
          }
          sh '''#! /bin/bash
                set -e
                if grep -q 'docker-baseimage' <<< "${LS_REPO}"; then
                  echo "Detected baseimage, setting LSIO_FIRST_PARTY=true"
                  if [ -n "${CI_DOCKERENV}" ]; then
                    CI_DOCKERENV="LSIO_FIRST_PARTY=true|${CI_DOCKERENV}"
                  else
                    CI_DOCKERENV="LSIO_FIRST_PARTY=true"
                  fi
                fi
                docker pull ghcr.io/linuxserver/ci:latest
                if [ "${MULTIARCH}" == "true" ]; then
                  docker pull ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER} --platform=arm64
                  docker tag ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER} ${IMAGE}:arm64v8-${META_TAG}
                fi
                docker run --rm \
                --shm-size=1gb \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -e IMAGE=\"${IMAGE}\" \
                -e DOCKER_LOGS_TIMEOUT=\"${CI_DELAY}\" \
                -e TAGS=\"${CI_TAGS}\" \
                -e META_TAG=\"${META_TAG}\" \
                -e RELEASE_TAG=\"ubuntu-mate\" \
                -e PORT=\"${CI_PORT}\" \
                -e SSL=\"${CI_SSL}\" \
                -e BASE=\"${DIST_IMAGE}\" \
                -e SECRET_KEY=\"${S3_SECRET}\" \
                -e ACCESS_KEY=\"${S3_KEY}\" \
                -e DOCKER_ENV=\"${CI_DOCKERENV}\" \
                -e WEB_SCREENSHOT=\"${CI_WEB}\" \
                -e WEB_AUTH=\"${CI_AUTH}\" \
                -e WEB_PATH=\"${CI_WEBPATH}\" \
                -e NODE_NAME=\"${NODE_NAME}\" \
                -t ghcr.io/linuxserver/ci:latest \
                python3 test_build.py'''
        }
      }
    }
    /* ##################
         Release Logic
       ################## */
    // If this is an amd64 only image only push a single image
    stage('Docker-Push-Single') {
      when {
        environment name: 'MULTIARCH', value: 'false'
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        retry_backoff(5,5) {
          sh '''#! /bin/bash
                set -e
                for PUSHIMAGE in "${IMAGE}" "${GITLABIMAGE}" "${GITHUBIMAGE}" "${QUAYIMAGE}"; do
                  [[ ${PUSHIMAGE%%/*} =~ \\. ]] && PUSHIMAGEPLUS="${PUSHIMAGE}" || PUSHIMAGEPLUS="docker.io/${PUSHIMAGE}"
                  IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                  for i in "${CACHE[@]}"; do
                      if [[ "${PUSHIMAGEPLUS}" == "$(cut -d "/" -f1 <<< ${i})"* ]]; then
                          CACHEIMAGE=${i}
                      fi
                  done
                  docker buildx imagetools create --prefer-index=false -t ${PUSHIMAGE}:${META_TAG} -t ${PUSHIMAGE}:ubuntu-mate -t ${PUSHIMAGE}:${EXT_RELEASE_TAG} ${CACHEIMAGE}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
                  if [ -n "${SEMVER}" ]; then
                    docker buildx imagetools create --prefer-index=false -t ${PUSHIMAGE}:${SEMVER} ${CACHEIMAGE}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
                  fi
                done
              '''
        }
      }
    }
    // If this is a multi arch release push all images and define the manifest
    stage('Docker-Push-Multi') {
      when {
        environment name: 'MULTIARCH', value: 'true'
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        retry_backoff(5,5) {
          sh '''#! /bin/bash
                set -e
                for MANIFESTIMAGE in "${IMAGE}" "${GITLABIMAGE}" "${GITHUBIMAGE}" "${QUAYIMAGE}"; do
                  [[ ${MANIFESTIMAGE%%/*} =~ \\. ]] && MANIFESTIMAGEPLUS="${MANIFESTIMAGE}" || MANIFESTIMAGEPLUS="docker.io/${MANIFESTIMAGE}"
                  IFS=',' read -ra CACHE <<< "$BUILDCACHE"
                  for i in "${CACHE[@]}"; do
                      if [[ "${MANIFESTIMAGEPLUS}" == "$(cut -d "/" -f1 <<< ${i})"* ]]; then
                          CACHEIMAGE=${i}
                      fi
                  done
                  docker buildx imagetools create --prefer-index=false -t ${MANIFESTIMAGE}:amd64-${META_TAG} -t ${MANIFESTIMAGE}:amd64-ubuntu-mate -t ${MANIFESTIMAGE}:amd64-${EXT_RELEASE_TAG} ${CACHEIMAGE}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
                  docker buildx imagetools create --prefer-index=false -t ${MANIFESTIMAGE}:arm64v8-${META_TAG} -t ${MANIFESTIMAGE}:arm64v8-ubuntu-mate -t ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG} ${CACHEIMAGE}:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}
                  if [ -n "${SEMVER}" ]; then
                    docker buildx imagetools create --prefer-index=false -t ${MANIFESTIMAGE}:amd64-${SEMVER} ${CACHEIMAGE}:amd64-${COMMIT_SHA}-${BUILD_NUMBER}
                    docker buildx imagetools create --prefer-index=false -t ${MANIFESTIMAGE}:arm64v8-${SEMVER} ${CACHEIMAGE}:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}
                  fi
                done
                for MANIFESTIMAGE in "${IMAGE}" "${GITLABIMAGE}" "${GITHUBIMAGE}" "${QUAYIMAGE}"; do
                  docker buildx imagetools create -t ${MANIFESTIMAGE}:ubuntu-mate ${MANIFESTIMAGE}:amd64-ubuntu-mate ${MANIFESTIMAGE}:arm64v8-ubuntu-mate
                  docker buildx imagetools create -t ${MANIFESTIMAGE}:${META_TAG} ${MANIFESTIMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:arm64v8-${META_TAG}

                  docker buildx imagetools create -t ${MANIFESTIMAGE}:${EXT_RELEASE_TAG} ${MANIFESTIMAGE}:amd64-${EXT_RELEASE_TAG} ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG}
                  if [ -n "${SEMVER}" ]; then
                    docker buildx imagetools create -t ${MANIFESTIMAGE}:${SEMVER} ${MANIFESTIMAGE}:amd64-${SEMVER} ${MANIFESTIMAGE}:arm64v8-${SEMVER}
                  fi
                done
              '''
        }
      }
    }
    // If this is a public release tag it in the LS Github
    stage('Github-Tag-Push-Release') {
      when {
        branch "ubuntu-mate"
        expression {
          env.LS_RELEASE != env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
        }
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        echo "Pushing New tag for current commit ${META_TAG}"
        sh '''curl -H "Authorization: token ${GITHUB_TOKEN}" -X POST https://api.github.com/repos/${LS_USER}/${LS_REPO}/git/tags \
        -d '{"tag":"'${META_TAG}'",\
             "object": "'${COMMIT_SHA}'",\
             "message": "Tagging Release '${EXT_RELEASE_CLEAN}'-ls'${LS_TAG_NUMBER}' to ubuntu-mate",\
             "type": "commit",\
             "tagger": {"name": "LinuxServer-CI","email": "ci@linuxserver.io","date": "'${GITHUB_DATE}'"}}' '''
        echo "Pushing New release for Tag"
        sh '''#! /bin/bash
              echo "Updating base packages to ${PACKAGE_TAG}" > releasebody.json
              echo '{"tag_name":"'${META_TAG}'",\
                     "target_commitish": "ubuntu-mate",\
                     "name": "'${META_TAG}'",\
                     "body": "**CI Report:**\\n\\n'${CI_URL:-N/A}'\\n\\n**LinuxServer Changes:**\\n\\n'${LS_RELEASE_NOTES}'\\n\\n**Remote Changes:**\\n\\n' > start
              printf '","draft": false,"prerelease": true}' >> releasebody.json
              paste -d'\\0' start releasebody.json > releasebody.json.done
              curl -H "Authorization: token ${GITHUB_TOKEN}" -X POST https://api.github.com/repos/${LS_USER}/${LS_REPO}/releases -d @releasebody.json.done'''
      }
    }
    // Add protection to the release branch
    stage('Github-Release-Branch-Protection') {
      when {
        branch "ubuntu-mate"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        echo "Setting up protection for release branch ubuntu-mate"
        sh '''#! /bin/bash
          curl -H "Authorization: token ${GITHUB_TOKEN}" -X PUT https://api.github.com/repos/${LS_USER}/${LS_REPO}/branches/ubuntu-mate/protection \
          -d $(jq -c .  << EOF
            {
              "required_status_checks": null,
              "enforce_admins": false,
              "required_pull_request_reviews": {
                "dismiss_stale_reviews": false,
                "require_code_owner_reviews": false,
                "require_last_push_approval": false,
                "required_approving_review_count": 1
              },
              "restrictions": null,
              "required_linear_history": false,
              "allow_force_pushes": false,
              "allow_deletions": false,
              "block_creations": false,
              "required_conversation_resolution": true,
              "lock_branch": false,
              "allow_fork_syncing": false,
              "required_signatures": false
            }
EOF
          ) '''
      }
    }
    // If this is a Pull request send the CI link as a comment on it
    stage('Pull Request Comment') {
      when {
        not {environment name: 'CHANGE_ID', value: ''}
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        sh '''#! /bin/bash
            # Function to retrieve JSON data from URL
            get_json() {
              local url="$1"
              local response=$(curl -s "$url")
              if [ $? -ne 0 ]; then
                echo "Failed to retrieve JSON data from $url"
                return 1
              fi
              local json=$(echo "$response" | jq .)
              if [ $? -ne 0 ]; then
                echo "Failed to parse JSON data from $url"
                return 1
              fi
              echo "$json"
            }

            build_table() {
              local data="$1"

              # Get the keys in the JSON data
              local keys=$(echo "$data" | jq -r 'to_entries | map(.key) | .[]')

              # Check if keys are empty
              if [ -z "$keys" ]; then
                echo "JSON report data does not contain any keys or the report does not exist."
                return 1
              fi

              # Build table header
              local header="| Tag | Passed |\\n| --- | --- |\\n"

              # Loop through the JSON data to build the table rows
              local rows=""
              for build in $keys; do
                local status=$(echo "$data" | jq -r ".[\\"$build\\"].test_success")
                if [ "$status" = "true" ]; then
                  status="✅"
                else
                  status="❌"
                fi
                local row="| "$build" | "$status" |\\n"
                rows="${rows}${row}"
              done

              local table="${header}${rows}"
              local escaped_table=$(echo "$table" | sed 's/\"/\\\\"/g')
              echo "$escaped_table"
            }

            if [[ "${CI}" = "true" ]]; then
              # Retrieve JSON data from URL
              data=$(get_json "$CI_JSON_URL")
              # Create table from JSON data
              table=$(build_table "$data")
              echo -e "$table"

              curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$LS_USER/$LS_REPO/issues/$PULL_REQUEST/comments" \
                -d "{\\"body\\": \\"I am a bot, here are the test results for this PR: \\n${CI_URL}\\n${SHELLCHECK_URL}\\n${table}\\"}"
            else
              curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$LS_USER/$LS_REPO/issues/$PULL_REQUEST/comments" \
                -d "{\\"body\\": \\"I am a bot, here is the pushed image/manifest for this PR: \\n\\n\\`${GITHUBIMAGE}:${META_TAG}\\`\\"}"
            fi
            '''

      }
    }
  }
  /* ######################
     Send status to Discord
     ###################### */
  post {
    always {
      sh '''#!/bin/bash
            rm -rf /config/.ssh/id_sign
            rm -rf /config/.ssh/id_sign.pub
            git config --global --unset gpg.format
            git config --global --unset user.signingkey
            git config --global --unset commit.gpgsign
        '''
      script{
        env.JOB_DATE = sh(
            script: '''date '+%Y-%m-%dT%H:%M:%S%:z' ''',
            returnStdout: true).trim()
        if (env.EXIT_STATUS == "ABORTED"){
          sh 'echo "build aborted"'
        }else{
          if (currentBuild.currentResult == "SUCCESS"){
            if (env.GITHUBIMAGE =~ /lspipepr/){
              env.JOB_WEBHOOK_STATUS='Success'
              env.JOB_WEBHOOK_COLOUR=3957028
              env.JOB_WEBHOOK_FOOTER='PR Build'
            }else if (env.GITHUBIMAGE =~ /lsiodev/){
              env.JOB_WEBHOOK_STATUS='Success'
              env.JOB_WEBHOOK_COLOUR=3957028
              env.JOB_WEBHOOK_FOOTER='Dev Build'
            }else{
              env.JOB_WEBHOOK_STATUS='Success'
              env.JOB_WEBHOOK_COLOUR=1681177
              env.JOB_WEBHOOK_FOOTER='Live Build'
            }
          }else{
            if (env.GITHUBIMAGE =~ /lspipepr/){
              env.JOB_WEBHOOK_STATUS='Failure'
              env.JOB_WEBHOOK_COLOUR=12669523
              env.JOB_WEBHOOK_FOOTER='PR Build'
            }else if (env.GITHUBIMAGE =~ /lsiodev/){
              env.JOB_WEBHOOK_STATUS='Failure'
              env.JOB_WEBHOOK_COLOUR=12669523
              env.JOB_WEBHOOK_FOOTER='Dev Build'
            }else{
              env.JOB_WEBHOOK_STATUS='Failure'
              env.JOB_WEBHOOK_COLOUR=16711680
              env.JOB_WEBHOOK_FOOTER='Live Build'
            }
          }
          sh ''' curl -X POST -H "Content-Type: application/json" --data '{"avatar_url": "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/jenkins-avatar.png","embeds": [{"'color'": '${JOB_WEBHOOK_COLOUR}',\
                 "footer": {"text" : "'"${JOB_WEBHOOK_FOOTER}"'"},\
                 "timestamp": "'${JOB_DATE}'",\
                 "description": "**Build:**  '${BUILD_NUMBER}'\\n**CI Results:**  '${CI_URL}'\\n**ShellCheck Results:**  '${SHELLCHECK_URL}'\\n**Status:**  '${JOB_WEBHOOK_STATUS}'\\n**Job:** '${RUN_DISPLAY_URL}'\\n**Change:** '${CODE_URL}'\\n**External Release:**: '${RELEASE_LINK}'\\n**DockerHub:** '${DOCKERHUB_LINK}'\\n"}],\
                 "username": "Jenkins"}' ${BUILDS_DISCORD} '''
        }
      }
    }
    cleanup {
      sh '''#! /bin/bash
            echo "Performing docker system prune!!"
            containers=$(docker ps -aq)
            if [[ -n "${containers}" ]]; then
              docker stop ${containers}
            fi
            docker system prune -af --volumes || :
         '''
      cleanWs()
    }
  }
}

def retry_backoff(int max_attempts, int power_base, Closure c) {
  int n = 0
  while (n < max_attempts) {
    try {
      c()
      return
    } catch (err) {
      if ((n + 1) >= max_attempts) {
        throw err
      }
      sleep(power_base ** n)
      n++
    }
  }
  return
}
