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
    SCARF_TOKEN=credentials('scarf_api_key')
    BUILD_VERSION_ARG = 'ICE_VERSION'
    LS_USER = 'linuxserver'
    LS_REPO = 'docker-webtop'
    CONTAINER_NAME = 'webtop'
    DOCKERHUB_IMAGE = 'linuxserver/webtop'
    DEV_DOCKERHUB_IMAGE = 'lsiodev/webtop'
    PR_DOCKERHUB_IMAGE = 'lspipepr/webtop'
    DIST_IMAGE = 'arch'
    MULTIARCH = 'true'
    CI = 'true'
    CI_WEB = 'true'
    CI_PORT = '3000'
    CI_SSL = 'false'
    CI_DELAY = '120'
    CI_DOCKERENV = 'TZ=US/Pacific'
    CI_AUTH = 'user:password'
    CI_WEBPATH = ''
  }
  stages {
    // Setup all the basic environment variables needed for the build
    stage("Set ENV Variables base"){
      steps{
        sh '''#! /bin/bash
              containers=$(docker ps -aq)
              if [[ -n "${containers}" ]]; then
                docker stop ${containers}
              fi
              docker system prune -af --volumes || : '''
        script{
          env.EXIT_STATUS = ''
          env.LS_RELEASE = sh(
            script: '''docker run --rm quay.io/skopeo/stable:v1 inspect docker://ghcr.io/${LS_USER}/${CONTAINER_NAME}:arch-icewm 2>/dev/null | jq -r '.Labels.build_version' | awk '{print $3}' | grep '\\-ls' || : ''',
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
          env.CODE_URL = 'https://github.com/' + env.LS_USER + '/' + env.LS_REPO + '/commit/' + env.GIT_COMMIT
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.DOCKERHUB_IMAGE + '/tags/'
          env.PULL_REQUEST = env.CHANGE_ID
          env.TEMPLATED_FILES = 'Jenkinsfile README.md LICENSE .editorconfig ./.github/CONTRIBUTING.md ./.github/FUNDING.yml ./.github/ISSUE_TEMPLATE/config.yml ./.github/ISSUE_TEMPLATE/issue.bug.yml ./.github/ISSUE_TEMPLATE/issue.feature.yml ./.github/PULL_REQUEST_TEMPLATE.md ./.github/workflows/external_trigger_scheduler.yml ./.github/workflows/greetings.yml ./.github/workflows/package_trigger_scheduler.yml ./.github/workflows/call_issue_pr_tracker.yml ./.github/workflows/call_issues_cron.yml ./.github/workflows/permissions.yml ./.github/workflows/external_trigger.yml ./.github/workflows/package_trigger.yml'
        }
        script{
          env.LS_RELEASE_NUMBER = sh(
            script: '''echo ${LS_RELEASE} |sed 's/^.*-ls//g' ''',
            returnStdout: true).trim()
        }
        script{
          env.LS_TAG_NUMBER = sh(
            script: '''#! /bin/bash
                       tagsha=$(git rev-list -n 1 arch-icewm-${LS_RELEASE} 2>/dev/null)
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
    // If this is a custom command to determine version use that command
    stage("Set tag custom bash"){
      steps{
        script{
          env.EXT_RELEASE = sh(
            script: ''' curl -sX GET https://api.github.com/repos/linuxserver/docker-baseimage-kasmvnc/releases | jq -r 'first(.[] | select(.tag_name | startswith("arch-"))) | .tag_name' | sed 's|arch-||' | sed 's|-ls.*||' ''',
            returnStdout: true).trim()
            env.RELEASE_LINK = 'custom_command'
        }
      }
    }
    // Sanitize the release tag and strip illegal docker or github characters
    stage("Sanitize tag"){
      steps{
        script{
          env.EXT_RELEASE_CLEAN = sh(
            script: '''echo ${EXT_RELEASE} | sed 's/[~,%@+;:/]//g' ''',
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
            if (BRANCH_NAME != "master" && BRANCH_NAME != "main") {
              env.SEMVER = "${env.SEMVER}-${BRANCH_NAME}"
            }
            println("SEMVER: ${env.SEMVER}")
          } else {
            println("No SEMVER detected")
          }

        }
      }
    }
    // If this is a arch-icewm build use live docker endpoints
    stage("Set ENV live build"){
      when {
        branch "arch-icewm"
        environment name: 'CHANGE_ID', value: ''
      }
      steps {
        script{
          env.IMAGE = env.DOCKERHUB_IMAGE
          env.GITHUBIMAGE = 'ghcr.io/' + env.LS_USER + '/' + env.CONTAINER_NAME
          env.GITLABIMAGE = 'registry.gitlab.com/linuxserver.io/' + env.LS_REPO + '/' + env.CONTAINER_NAME
          env.QUAYIMAGE = 'quay.io/linuxserver.io/' + env.CONTAINER_NAME
          if (env.MULTIARCH == 'true') {
            env.CI_TAGS = 'amd64-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER + '|arm64v8-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          } else {
            env.CI_TAGS = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          env.META_TAG = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-ls' + env.LS_TAG_NUMBER
          env.EXT_RELEASE_TAG = 'arch-icewm-version-' + env.EXT_RELEASE_CLEAN
        }
      }
    }
    // If this is a dev build use dev docker endpoints
    stage("Set ENV dev build"){
      when {
        not {branch "arch-icewm"}
        environment name: 'CHANGE_ID', value: ''
      }
      steps {
        script{
          env.IMAGE = env.DEV_DOCKERHUB_IMAGE
          env.GITHUBIMAGE = 'ghcr.io/' + env.LS_USER + '/lsiodev-' + env.CONTAINER_NAME
          env.GITLABIMAGE = 'registry.gitlab.com/linuxserver.io/' + env.LS_REPO + '/lsiodev-' + env.CONTAINER_NAME
          env.QUAYIMAGE = 'quay.io/linuxserver.io/lsiodev-' + env.CONTAINER_NAME
          if (env.MULTIARCH == 'true') {
            env.CI_TAGS = 'amd64-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '|arm64v8-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          } else {
            env.CI_TAGS = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          env.META_TAG = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA
          env.EXT_RELEASE_TAG = 'arch-icewm-version-' + env.EXT_RELEASE_CLEAN
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.DEV_DOCKERHUB_IMAGE + '/tags/'
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
            env.CI_TAGS = 'amd64-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST + '|arm64v8-arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          } else {
            env.CI_TAGS = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          }
          env.VERSION_TAG = env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          env.META_TAG = 'arch-icewm-' + env.EXT_RELEASE_CLEAN + '-pkg-' + env.PACKAGE_TAG + '-dev-' + env.COMMIT_SHA + '-pr-' + env.PULL_REQUEST
          env.EXT_RELEASE_TAG = 'arch-icewm-version-' + env.EXT_RELEASE_CLEAN
          env.CODE_URL = 'https://github.com/' + env.LS_USER + '/' + env.LS_REPO + '/pull/' + env.PULL_REQUEST
          env.DOCKERHUB_LINK = 'https://hub.docker.com/r/' + env.PR_DOCKERHUB_IMAGE + '/tags/'
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
                  ghcr.io/linuxserver/baseimage-alpine:3.17 s6-envdir -fn -- /var/run/s6/container_environment /bin/bash -c "\
                    apk add --no-cache py3-pip && \
                    pip install s3cmd && \
                    s3cmd put --no-preserve --acl-public -m text/xml /mnt/shellcheck-result.xml s3://ci-tests.linuxserver.io/${IMAGE}/${META_TAG}/shellcheck-result.xml" || :'''
        }
      }
    }
    // Use helper containers to render templated files
    stage('Update-Templates') {
      when {
        branch "arch-icewm"
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
              docker run --rm -e CONTAINER_NAME=${CONTAINER_NAME} -e GITHUB_BRANCH=arch-icewm -v ${TEMPDIR}:/ansible/jenkins ghcr.io/linuxserver/jenkins-builder:latest 
              # Stage 1 - Jenkinsfile update
              if [[ "$(md5sum Jenkinsfile | awk '{ print $1 }')" != "$(md5sum ${TEMPDIR}/docker-${CONTAINER_NAME}/Jenkinsfile | awk '{ print $1 }')" ]]; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f arch-icewm
                cp ${TEMPDIR}/docker-${CONTAINER_NAME}/Jenkinsfile ${TEMPDIR}/repo/${LS_REPO}/
                git add Jenkinsfile
                git commit -m 'Bot Updating Templated Files'
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git --all
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Updating Jenkinsfile"
                rm -Rf ${TEMPDIR}
                exit 0
              else
                echo "Jenkinsfile is up to date."
              fi
              # Stage 2 - Delete old templates
              OLD_TEMPLATES=".github/ISSUE_TEMPLATE.md .github/ISSUE_TEMPLATE/issue.bug.md .github/ISSUE_TEMPLATE/issue.feature.md .github/workflows/call_invalid_helper.yml .github/workflows/stale.yml Dockerfile.armhf"
              for i in ${OLD_TEMPLATES}; do
                if [[ -f "${i}" ]]; then
                  TEMPLATES_TO_DELETE="${i} ${TEMPLATES_TO_DELETE}"
                fi
              done
              if [[ -n "${TEMPLATES_TO_DELETE}" ]]; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f arch-icewm
                for i in ${TEMPLATES_TO_DELETE}; do
                  git rm "${i}"
                done
                git commit -m 'Bot Updating Templated Files'
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git --all
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
                echo "Deleting old and deprecated templates"
                rm -Rf ${TEMPDIR}
                exit 0
              else
                echo "No templates to delete"
              fi
              # Stage 3 - Update templates
              CURRENTHASH=$(grep -hs ^ ${TEMPLATED_FILES} | md5sum | cut -c1-8)
              cd ${TEMPDIR}/docker-${CONTAINER_NAME}
              NEWHASH=$(grep -hs ^ ${TEMPLATED_FILES} | md5sum | cut -c1-8)
              if [[ "${CURRENTHASH}" != "${NEWHASH}" ]] || ! grep -q '.jenkins-external' "${WORKSPACE}/.gitignore" 2>/dev/null; then
                mkdir -p ${TEMPDIR}/repo
                git clone https://github.com/${LS_USER}/${LS_REPO}.git ${TEMPDIR}/repo/${LS_REPO}
                cd ${TEMPDIR}/repo/${LS_REPO}
                git checkout -f arch-icewm
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
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git --all
                echo "true" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
              else
                echo "false" > /tmp/${COMMIT_SHA}-${BUILD_NUMBER}
              fi
              mkdir -p ${TEMPDIR}/gitbook
              git clone https://github.com/linuxserver/docker-documentation.git ${TEMPDIR}/gitbook/docker-documentation
              if [[ ("${BRANCH_NAME}" == "master") || ("${BRANCH_NAME}" == "main") ]] && [[ (! -f ${TEMPDIR}/gitbook/docker-documentation/images/docker-${CONTAINER_NAME}.md) || ("$(md5sum ${TEMPDIR}/gitbook/docker-documentation/images/docker-${CONTAINER_NAME}.md | awk '{ print $1 }')" != "$(md5sum ${TEMPDIR}/docker-${CONTAINER_NAME}/.jenkins-external/docker-${CONTAINER_NAME}.md | awk '{ print $1 }')") ]]; then
                cp ${TEMPDIR}/docker-${CONTAINER_NAME}/.jenkins-external/docker-${CONTAINER_NAME}.md ${TEMPDIR}/gitbook/docker-documentation/images/
                cd ${TEMPDIR}/gitbook/docker-documentation/
                git add images/docker-${CONTAINER_NAME}.md
                git commit -m 'Bot Updating Documentation'
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/linuxserver/docker-documentation.git --all
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
        branch "arch-icewm"
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
    // If this is a arch-icewm build check the S6 service file perms
    stage("Check S6 Service file Permissions"){
      when {
        branch "arch-icewm"
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
           GitLab Mirroring
       ####################### */
    // Ping into Gitlab to mirror this repo and have a registry endpoint
    stage("GitLab Mirror"){
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
      } 
    }
    /* #######################
           Scarf.sh package registry
       ####################### */
    // Add package to Scarf.sh and set permissions
    stage("Scarf.sh package registry"){
      when {
        branch "arch-icewm"
        environment name: 'EXIT_STATUS', value: ''
      }
      steps{
        sh '''#! /bin/bash
              PACKAGE_UUID=$(curl -X GET -H "Authorization: Bearer ${SCARF_TOKEN}" https://scarf.sh/api/v1/organizations/linuxserver-ci/packages | jq -r '.[] | select(.name=="linuxserver/webtop") | .uuid' || :)
              if [ -z "${PACKAGE_UUID}" ]; then
                echo "Adding package to Scarf.sh"
                curl -sX POST https://scarf.sh/api/v1/organizations/linuxserver-ci/packages \
                  -H "Authorization: Bearer ${SCARF_TOKEN}" \
                  -H "Content-Type: application/json" \
                  -d '{"name":"linuxserver/webtop",\
                       "shortDescription":"example description",\
                       "libraryType":"docker",\
                       "website":"https://github.com/linuxserver/docker-webtop",\
                       "backendUrl":"https://ghcr.io/linuxserver/webtop",\
                       "publicUrl":"https://lscr.io/linuxserver/webtop"}' || :
              else
                echo "Package already exists on Scarf.sh"
              fi
           '''
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
          --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
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
              --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
          }
        }
        stage('Build ARM64') {
          agent {
            label 'ARM64'
          }
          steps {
            echo "Running on node: ${NODE_NAME}"
            echo 'Logging into Github'
            sh '''#! /bin/bash
                  echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
               '''
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
              --build-arg ${BUILD_VERSION_ARG}=${EXT_RELEASE} --build-arg VERSION=\"${VERSION_TAG}\" --build-arg BUILD_DATE=${GITHUB_DATE} ."
            sh "docker tag ${IMAGE}:arm64v8-${META_TAG} ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}"
            retry(5) {
              sh "docker push ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}"
            }
            sh '''#! /bin/bash
                  containers=$(docker ps -aq)
                  if [[ -n "${containers}" ]]; then
                    docker stop ${containers}
                  fi
                  docker system prune -af --volumes || : '''
          }
        }
      }
    }
    // Take the image we just built and dump package versions for comparison
    stage('Update-packages') {
      when {
        branch "arch-icewm"
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        sh '''#! /bin/bash
              set -e
              TEMPDIR=$(mktemp -d)
              if [ "${MULTIARCH}" == "true" ] && [ "${PACKAGE_CHECK}" == "false" ]; then
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
                git --git-dir ${TEMPDIR}/${LS_REPO}/.git checkout -f arch-icewm
                cp ${TEMPDIR}/package_versions.txt ${TEMPDIR}/${LS_REPO}/
                cd ${TEMPDIR}/${LS_REPO}/
                wait
                git add package_versions.txt
                git commit -m 'Bot Updating Package Versions'
                git push https://LinuxServer-CI:${GITHUB_TOKEN}@github.com/${LS_USER}/${LS_REPO}.git --all
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
        branch "arch-icewm"
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
        branch "arch-icewm"
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
                docker pull ghcr.io/linuxserver/ci:latest
                if [ "${MULTIARCH}" == "true" ]; then
                  docker pull ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}
                  docker tag ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER} ${IMAGE}:arm64v8-${META_TAG}
                fi
                docker run --rm \
                --shm-size=1gb \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -e IMAGE=\"${IMAGE}\" \
                -e DELAY_START=\"${CI_DELAY}\" \
                -e TAGS=\"${CI_TAGS}\" \
                -e META_TAG=\"${META_TAG}\" \
                -e PORT=\"${CI_PORT}\" \
                -e SSL=\"${CI_SSL}\" \
                -e BASE=\"${DIST_IMAGE}\" \
                -e SECRET_KEY=\"${S3_SECRET}\" \
                -e ACCESS_KEY=\"${S3_KEY}\" \
                -e DOCKER_ENV=\"${CI_DOCKERENV}\" \
                -e WEB_SCREENSHOT=\"${CI_WEB}\" \
                -e WEB_AUTH=\"${CI_AUTH}\" \
                -e WEB_PATH=\"${CI_WEBPATH}\" \
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
        withCredentials([
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: '3f9ba4d5-100d-45b0-a3c4-633fd6061207',
            usernameVariable: 'DOCKERUSER',
            passwordVariable: 'DOCKERPASS'
          ],
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: 'Quay.io-Robot',
            usernameVariable: 'QUAYUSER',
            passwordVariable: 'QUAYPASS'
          ]
        ]) {
          retry(5) {
            sh '''#! /bin/bash
                  set -e
                  echo $DOCKERPASS | docker login -u $DOCKERUSER --password-stdin
                  echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
                  echo $GITLAB_TOKEN | docker login registry.gitlab.com -u LinuxServer.io --password-stdin
                  echo $QUAYPASS | docker login quay.io -u $QUAYUSER --password-stdin
                  for PUSHIMAGE in "${GITHUBIMAGE}" "${GITLABIMAGE}" "${QUAYIMAGE}" "${IMAGE}"; do
                    docker tag ${IMAGE}:${META_TAG} ${PUSHIMAGE}:${META_TAG}
                    docker tag ${PUSHIMAGE}:${META_TAG} ${PUSHIMAGE}:arch-icewm
                    docker tag ${PUSHIMAGE}:${META_TAG} ${PUSHIMAGE}:${EXT_RELEASE_TAG}
                    if [ -n "${SEMVER}" ]; then
                      docker tag ${PUSHIMAGE}:${META_TAG} ${PUSHIMAGE}:${SEMVER}
                    fi
                    docker push ${PUSHIMAGE}:arch-icewm
                    docker push ${PUSHIMAGE}:${META_TAG}
                    docker push ${PUSHIMAGE}:${EXT_RELEASE_TAG}
                    if [ -n "${SEMVER}" ]; then
                     docker push ${PUSHIMAGE}:${SEMVER}
                    fi
                  done
               '''
          }
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
        withCredentials([
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: '3f9ba4d5-100d-45b0-a3c4-633fd6061207',
            usernameVariable: 'DOCKERUSER',
            passwordVariable: 'DOCKERPASS'
          ],
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: 'Quay.io-Robot',
            usernameVariable: 'QUAYUSER',
            passwordVariable: 'QUAYPASS'
          ]
        ]) {
          retry(5) {
            sh '''#! /bin/bash
                  set -e
                  echo $DOCKERPASS | docker login -u $DOCKERUSER --password-stdin
                  echo $GITHUB_TOKEN | docker login ghcr.io -u LinuxServer-CI --password-stdin
                  echo $GITLAB_TOKEN | docker login registry.gitlab.com -u LinuxServer.io --password-stdin
                  echo $QUAYPASS | docker login quay.io -u $QUAYUSER --password-stdin
                  if [ "${CI}" == "false" ]; then
                    docker pull ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER}
                    docker tag ghcr.io/linuxserver/lsiodev-buildcache:arm64v8-${COMMIT_SHA}-${BUILD_NUMBER} ${IMAGE}:arm64v8-${META_TAG}
                  fi
                  for MANIFESTIMAGE in "${IMAGE}" "${GITLABIMAGE}" "${GITHUBIMAGE}" "${QUAYIMAGE}"; do
                    docker tag ${IMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:amd64-${META_TAG}
                    docker tag ${MANIFESTIMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:amd64-arch-icewm
                    docker tag ${MANIFESTIMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:amd64-${EXT_RELEASE_TAG}
                    docker tag ${IMAGE}:arm64v8-${META_TAG} ${MANIFESTIMAGE}:arm64v8-${META_TAG}
                    docker tag ${MANIFESTIMAGE}:arm64v8-${META_TAG} ${MANIFESTIMAGE}:arm64v8-arch-icewm
                    docker tag ${MANIFESTIMAGE}:arm64v8-${META_TAG} ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG}
                    if [ -n "${SEMVER}" ]; then
                      docker tag ${MANIFESTIMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:amd64-${SEMVER}
                      docker tag ${MANIFESTIMAGE}:arm64v8-${META_TAG} ${MANIFESTIMAGE}:arm64v8-${SEMVER}
                    fi
                    docker push ${MANIFESTIMAGE}:amd64-${META_TAG}
                    docker push ${MANIFESTIMAGE}:amd64-${EXT_RELEASE_TAG}
                    docker push ${MANIFESTIMAGE}:amd64-arch-icewm
                    docker push ${MANIFESTIMAGE}:arm64v8-${META_TAG}
                    docker push ${MANIFESTIMAGE}:arm64v8-arch-icewm
                    docker push ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG}
                    if [ -n "${SEMVER}" ]; then
                      docker push ${MANIFESTIMAGE}:amd64-${SEMVER}
                      docker push ${MANIFESTIMAGE}:arm64v8-${SEMVER}
                    fi
                    docker manifest push --purge ${MANIFESTIMAGE}:arch-icewm || :
                    docker manifest create ${MANIFESTIMAGE}:arch-icewm ${MANIFESTIMAGE}:amd64-arch-icewm ${MANIFESTIMAGE}:arm64v8-arch-icewm
                    docker manifest annotate ${MANIFESTIMAGE}:arch-icewm ${MANIFESTIMAGE}:arm64v8-arch-icewm --os linux --arch arm64 --variant v8
                    docker manifest push --purge ${MANIFESTIMAGE}:${META_TAG} || :
                    docker manifest create ${MANIFESTIMAGE}:${META_TAG} ${MANIFESTIMAGE}:amd64-${META_TAG} ${MANIFESTIMAGE}:arm64v8-${META_TAG}
                    docker manifest annotate ${MANIFESTIMAGE}:${META_TAG} ${MANIFESTIMAGE}:arm64v8-${META_TAG} --os linux --arch arm64 --variant v8
                    docker manifest push --purge ${MANIFESTIMAGE}:${EXT_RELEASE_TAG} || :
                    docker manifest create ${MANIFESTIMAGE}:${EXT_RELEASE_TAG} ${MANIFESTIMAGE}:amd64-${EXT_RELEASE_TAG} ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG}
                    docker manifest annotate ${MANIFESTIMAGE}:${EXT_RELEASE_TAG} ${MANIFESTIMAGE}:arm64v8-${EXT_RELEASE_TAG} --os linux --arch arm64 --variant v8
                    if [ -n "${SEMVER}" ]; then
                      docker manifest push --purge ${MANIFESTIMAGE}:${SEMVER} || :
                      docker manifest create ${MANIFESTIMAGE}:${SEMVER} ${MANIFESTIMAGE}:amd64-${SEMVER} ${MANIFESTIMAGE}:arm64v8-${SEMVER}
                      docker manifest annotate ${MANIFESTIMAGE}:${SEMVER} ${MANIFESTIMAGE}:arm64v8-${SEMVER} --os linux --arch arm64 --variant v8
                    fi
                    token=$(curl -sX GET "https://ghcr.io/token?scope=repository%3Alinuxserver%2F${CONTAINER_NAME}%3Apull" | jq -r '.token')
                    digest=$(curl -s \
                      --header "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                      --header "Authorization: Bearer ${token}" \
                      "https://ghcr.io/v2/linuxserver/${CONTAINER_NAME}/manifests/arm32v7-arch-icewm")
                    if [[ $(echo "$digest" | jq -r '.layers') != "null" ]]; then
                      docker manifest push --purge ${MANIFESTIMAGE}:arm32v7-arch-icewm || :
                      docker manifest create ${MANIFESTIMAGE}:arm32v7-arch-icewm ${MANIFESTIMAGE}:amd64-arch-icewm
                      docker manifest push --purge ${MANIFESTIMAGE}:arm32v7-arch-icewm
                    fi
                    docker manifest push --purge ${MANIFESTIMAGE}:arch-icewm
                    docker manifest push --purge ${MANIFESTIMAGE}:${META_TAG} 
                    docker manifest push --purge ${MANIFESTIMAGE}:${EXT_RELEASE_TAG} 
                    if [ -n "${SEMVER}" ]; then
                      docker manifest push --purge ${MANIFESTIMAGE}:${SEMVER} 
                    fi
                  done
               '''
          }
        }
      }
    }
    // If this is a public release tag it in the LS Github
    stage('Github-Tag-Push-Release') {
      when {
        branch "arch-icewm"
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
             "message": "Tagging Release '${EXT_RELEASE_CLEAN}'-ls'${LS_TAG_NUMBER}' to arch-icewm",\
             "type": "commit",\
             "tagger": {"name": "LinuxServer Jenkins","email": "jenkins@linuxserver.io","date": "'${GITHUB_DATE}'"}}' '''
        echo "Pushing New release for Tag"
        sh '''#! /bin/bash
              echo "Updating to ${EXT_RELEASE_CLEAN}" > releasebody.json
              echo '{"tag_name":"'${META_TAG}'",\
                     "target_commitish": "arch-icewm",\
                     "name": "'${META_TAG}'",\
                     "body": "**LinuxServer Changes:**\\n\\n'${LS_RELEASE_NOTES}'\\n\\n**Remote Changes:**\\n\\n' > start
              printf '","draft": false,"prerelease": true}' >> releasebody.json
              paste -d'\\0' start releasebody.json > releasebody.json.done
              curl -H "Authorization: token ${GITHUB_TOKEN}" -X POST https://api.github.com/repos/${LS_USER}/${LS_REPO}/releases -d @releasebody.json.done'''
      }
    }
    // Use helper container to sync the current README on master to the dockerhub endpoint
    stage('Sync-README') {
      when {
        environment name: 'CHANGE_ID', value: ''
        environment name: 'EXIT_STATUS', value: ''
      }
      steps {
        withCredentials([
          [
            $class: 'UsernamePasswordMultiBinding',
            credentialsId: '3f9ba4d5-100d-45b0-a3c4-633fd6061207',
            usernameVariable: 'DOCKERUSER',
            passwordVariable: 'DOCKERPASS'
          ]
        ]) {
          sh '''#! /bin/bash
                set -e
                TEMPDIR=$(mktemp -d)
                docker pull ghcr.io/linuxserver/jenkins-builder:latest
                docker run --rm -e CONTAINER_NAME=${CONTAINER_NAME} -e GITHUB_BRANCH="${BRANCH_NAME}" -v ${TEMPDIR}:/ansible/jenkins ghcr.io/linuxserver/jenkins-builder:latest
                docker pull ghcr.io/linuxserver/readme-sync
                docker run --rm=true \
                  -e DOCKERHUB_USERNAME=$DOCKERUSER \
                  -e DOCKERHUB_PASSWORD=$DOCKERPASS \
                  -e GIT_REPOSITORY=${LS_USER}/${LS_REPO} \
                  -e DOCKER_REPOSITORY=${IMAGE} \
                  -e GIT_BRANCH=master \
                  -v ${TEMPDIR}/docker-${CONTAINER_NAME}:/mnt \
                  ghcr.io/linuxserver/readme-sync bash -c 'node sync'
                rm -Rf ${TEMPDIR} '''
        }
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
      script{
        if (env.EXIT_STATUS == "ABORTED"){
          sh 'echo "build aborted"'
        }
        else if (currentBuild.currentResult == "SUCCESS"){
          sh ''' curl -X POST -H "Content-Type: application/json" --data '{"avatar_url": "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/jenkins-avatar.png","embeds": [{"color": 1681177,\
                 "description": "**Build:**  '${BUILD_NUMBER}'\\n**CI Results:**  '${CI_URL}'\\n**ShellCheck Results:**  '${SHELLCHECK_URL}'\\n**Status:**  Success\\n**Job:** '${RUN_DISPLAY_URL}'\\n**Change:** '${CODE_URL}'\\n**External Release:**: '${RELEASE_LINK}'\\n**DockerHub:** '${DOCKERHUB_LINK}'\\n"}],\
                 "username": "Jenkins"}' ${BUILDS_DISCORD} '''
        }
        else {
          sh ''' curl -X POST -H "Content-Type: application/json" --data '{"avatar_url": "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/jenkins-avatar.png","embeds": [{"color": 16711680,\
                 "description": "**Build:**  '${BUILD_NUMBER}'\\n**CI Results:**  '${CI_URL}'\\n**ShellCheck Results:**  '${SHELLCHECK_URL}'\\n**Status:**  failure\\n**Job:** '${RUN_DISPLAY_URL}'\\n**Change:** '${CODE_URL}'\\n**External Release:**: '${RELEASE_LINK}'\\n**DockerHub:** '${DOCKERHUB_LINK}'\\n"}],\
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
