#!/usr/bin/env bash
# Copyright Amazon.com Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e
set -x
set -o pipefail

export LANG=C.UTF-8

BASE_AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BASE_DIRECTORY=$(git rev-parse --show-toplevel)

. "${BASE_DIRECTORY}/generatebundlefile/hack/common.sh"
ORAS_BIN=${BASE_DIRECTORY}/bin/oras

make build
chmod +x ${BASE_DIRECTORY}/generatebundlefile/bin/generatebundlefile

# Release Helm Chart, and bundle to Staging account
cat << EOF > stagingconfigfile
[default]
region=us-west-2
account=$BASE_AWS_ACCOUNT_ID
output=json

[profile staging]
role_arn=$ARTIFACT_DEPLOYMENT_ROLE
region=us-east-1
credential_source=EcsContainer
EOF

export AWS_CONFIG_FILE=${BASE_DIRECTORY}/generatebundlefile/stagingconfigfile
export PROFILE=staging
. "${BASE_DIRECTORY}/generatebundlefile/hack/common.sh"

aws ecr-public get-login-password --region us-east-1 | HELM_EXPERIMENTAL_OCI=1 helm registry login --username AWS --password-stdin public.ecr.aws

file_name=staging_artifact_move.yaml
REGISTRY=${BASE_AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com
REPO=${REGISTRY}/eks-anywhere-packages-bundles

# Move Helm charts within the bundle to Public ECR
${BASE_DIRECTORY}/generatebundlefile/bin/generatebundlefile  \
    --input ${BASE_DIRECTORY}/generatebundlefile/data/${file_name} \
    --public-profile ${PROFILE}

if [ ! -x "${ORAS_BIN}" ]; then
    make oras-install
fi

# Generate Bundles from Public ECR
export AWS_PROFILE=staging
export AWS_CONFIG_FILE=${BASE_DIRECTORY}/generatebundlefile/stagingconfigfile
for version in 1-26 1-27 1-28 1-29 1-30; do
    generate ${version} "staging"
done

# Push Bundles to Public ECR
aws ecr-public get-login-password --region us-east-1 | HELM_EXPERIMENTAL_OCI=1 helm registry login --username AWS --password-stdin public.ecr.aws
for version in 1-26 1-27 1-28 1-29 1-30; do
    push ${version} "staging"
done
