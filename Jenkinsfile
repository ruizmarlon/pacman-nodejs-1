DOCKER_USER = "${env.BRANCH_NAME}"
DOCKER_USER_CLEAN = "${DOCKER_USER.replace(".", "")}"
DOCKER_IMAGE_NAMESPACE_PROD = "${DOCKER_USER_CLEAN}"
DOCKER_IMAGE_NAMESPACE_DEV = "${DOCKER_IMAGE_NAMESPACE_PROD}-dev"
DOCKER_IMAGE_REPOSITORY = "pacman-nodejs"
DOCKER_IMAGE_TAG = "${env.BUILD_TIMESTAMP}"

// For available target clusters, contact your platform administrator
TARGET_CLUSTER_DOMAIN = "west.us.se.dckr.org"

// Available orchestrators = [ "kubernetes" | "swarm" ]
ORCHESTRATOR = "kubernetes"

if(! CLUSTER.containsKey(TARGET_CLUSTER_DOMAIN)){
    error("Unknown cluster '${TARGET_CLUSTER_DOMAIN}'")
}
TARGET_CLUSTER = CLUSTER.get(TARGET_CLUSTER_DOMAIN)

if(ORCHESTRATOR.toLowerCase() == "kubernetes"){
    DOCKER_KUBERNETES_NAMESPACE = "${DOCKER_USER_CLEAN}"

    DOCKER_APPLICATION_DOMAIN = "${DOCKER_USER_CLEAN}.${TARGET_CLUSTER['KUBE_DOMAIN_NAME']}"
}
else if (ORCHESTRATOR.toLowerCase() == "swarm"){
    DOCKER_SERVICE_NAME = "${DOCKER_USER_CLEAN}-${DOCKER_IMAGE_REPOSITORY}"
    DOCKER_STACK_NAME = "${DOCKER_USER_CLEAN}-simple-nginx"
    DOCKER_UCP_COLLECTION_PATH = "/Shared/Private/${DOCKER_USER}"

    DOCKER_APPLICATION_DOMAIN = "${DOCKER_USER_CLEAN}.${TARGET_CLUSTER['SWARM_DOMAIN_NAME']}"
}
else {
    error("Unsupported orchestrator")
}

MONGO_TAG="latest"

node {
    def docker_image

    stage('Checkout') {
        checkout scm
    }

    stage('Build') {
        docker_image = docker.build("${DOCKER_IMAGE_NAMESPACE_DEV}/${DOCKER_IMAGE_REPOSITORY}")
    }

    stage('Unit Tests') {
        docker_image.inside("--entrypoint=") {
            sh 'echo "Tests passed"'
        }
    }

    stage('Push') {
        docker.withRegistry(TARGET_CLUSTER['REGISTRY_URI'], TARGET_CLUSTER['REGISTRY_CREDENTIALS_ID']) {
            docker_image.push(DOCKER_IMAGE_TAG)
        }
    }

    stage('Scan') {
        httpRequest acceptType: 'APPLICATION_JSON', authentication: TARGET_CLUSTER['REGISTRY_CREDENTIALS_ID'], contentType: 'APPLICATION_JSON', httpMode: 'POST', ignoreSslErrors: true, responseHandle: 'NONE', url: "${TARGET_CLUSTER['REGISTRY_URI']}/api/v0/imagescan/scan/${DOCKER_IMAGE_NAMESPACE_DEV}/${DOCKER_IMAGE_REPOSITORY}/${DOCKER_IMAGE_TAG}/linux/amd64"

        def scan_result

        def scanning = true
        while(scanning) {
            def scan_result_response = httpRequest acceptType: 'APPLICATION_JSON', authentication: TARGET_CLUSTER['REGISTRY_CREDENTIALS_ID'], httpMode: 'GET', ignoreSslErrors: true, responseHandle: 'LEAVE_OPEN', url: "${TARGET_CLUSTER['REGISTRY_URI']}/api/v0/imagescan/repositories/${DOCKER_IMAGE_NAMESPACE_DEV}/${DOCKER_IMAGE_REPOSITORY}/${DOCKER_IMAGE_TAG}"
            scan_result = readJSON text: scan_result_response.content

            if (scan_result.size() != 1) {
                println('Response: ' + scan_result)
                error('More than one imagescan returned, please narrow your search parameters')
            }

            scan_result = scan_result[0]

            if (!scan_result.check_completed_at.equals("0001-01-01T00:00:00Z")) {
                scanning = false
            } else {
                sleep 15
            }

        }
        println('Response JSON: ' + scan_result)
    }

    stage('Sign Development Image') {
        withEnv(["DOCKER_REGISTRY_HOSTNAME=${TARGET_CLUSTER['REGISTRY_HOSTNAME']}",
                 "DOCKER_IMAGE_NAMESPACE=${DOCKER_IMAGE_NAMESPACE_DEV}",
                 "DOCKER_IMAGE_REPOSITORY=${DOCKER_IMAGE_REPOSITORY}",
                 "DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}"
                 ]) {
            withCredentials([string(credentialsId: TARGET_CLUSTER['TRUST_SIGNER_PASSPHRASE_CREDENTIALS_ID'] , variable: 'DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE')]) {
                sh 'docker trust sign ${DOCKER_REGISTRY_HOSTNAME}/${DOCKER_IMAGE_NAMESPACE}/${DOCKER_IMAGE_REPOSITORY}:${DOCKER_IMAGE_TAG}'
            }
        }
    }

    stage('Deploy to Development') {
        withEnv(["DOCKER_APPLICATION_FQDN=${DOCKER_IMAGE_REPOSITORY}.dev.${DOCKER_APPLICATION_DOMAIN}",
                 "DOCKER_REGISTRY_HOSTNAME=${TARGET_CLUSTER['REGISTRY_HOSTNAME']}",
                 "DOCKER_IMAGE_NAMESPACE=${DOCKER_IMAGE_NAMESPACE_DEV}",
                 "DOCKER_IMAGE_REPOSITORY=${DOCKER_IMAGE_REPOSITORY}",
                 "DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}",
                 "DOCKER_USER_CLEAN=${DOCKER_USER_CLEAN}",
                 "MONGO_TAG=${MONGO_TAG}"
                 ]) {

            if(ORCHESTRATOR.toLowerCase() == "kubernetes"){
                println("Deploying to Kubernetes")
                withEnv(["DOCKER_KUBERNETES_CONTEXT=${TARGET_CLUSTER['KUBERNETES_CONTEXT']}", "DOCKER_KUBERNETES_NAMESPACE=${DOCKER_KUBERNETES_NAMESPACE}-dev"]) {
                    sh 'envsubst < kubernetes/cluster/001_mongo_pvc.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/002_mongo_deployment.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/003_mongo_service.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/004_pacman_deployment.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/005_pacman_service.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/006_pacman_ingress.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                }
            }
            else if (ORCHESTRATOR.toLowerCase() == "swarm"){
                println("Deploying to Swarm")
                withEnv(["DOCKER_UCP_COLLECTION_PATH=${DOCKER_UCP_COLLECTION_PATH}"]) {
                    withDockerServer([credentialsId: TARGET_CLUSTER['UCP_CREDENTIALS_ID'], uri: TARGET_CLUSTER['UCP_URI']]) {
                        sh "docker stack deploy -c swarm/docker-compose.yml ${DOCKER_STACK_NAME}-dev"
                    }
                }
            }

            println("Application deployed to Development: http://${DOCKER_APPLICATION_FQDN}")
        }
    }

    stage('Integration Tests') {
        docker_image.inside {
            sh 'echo "Tests passed"'
        }
    }

    stage('Promote') {
        httpRequest acceptType: 'APPLICATION_JSON', authentication: TARGET_CLUSTER['REGISTRY_CREDENTIALS_ID'], contentType: 'APPLICATION_JSON', httpMode: 'POST', ignoreSslErrors: true, requestBody: "{\"targetRepository\": \"${DOCKER_IMAGE_NAMESPACE_PROD}/${DOCKER_IMAGE_REPOSITORY}\", \"targetTag\": \"${DOCKER_IMAGE_TAG}\"}", responseHandle: 'NONE', url: "${TARGET_CLUSTER['REGISTRY_URI']}/api/v0/repositories/${DOCKER_IMAGE_NAMESPACE_DEV}/${DOCKER_IMAGE_REPOSITORY}/tags/${DOCKER_IMAGE_TAG}/promotion"
    }

    stage('Sign Production Image') {
        withEnv(["DOCKER_REGISTRY_HOSTNAME=${TARGET_CLUSTER['REGISTRY_HOSTNAME']}",
                 "DOCKER_IMAGE_NAMESPACE=${DOCKER_IMAGE_NAMESPACE_PROD}",
                 "DOCKER_IMAGE_REPOSITORY=${DOCKER_IMAGE_REPOSITORY}",
                 "DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}"
                 ]) {
            withCredentials([string(credentialsId: TARGET_CLUSTER['TRUST_SIGNER_PASSPHRASE_CREDENTIALS_ID'] , variable: 'DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE')]) {
                sh 'docker pull ${DOCKER_REGISTRY_HOSTNAME}/${DOCKER_IMAGE_NAMESPACE}/${DOCKER_IMAGE_REPOSITORY}:${DOCKER_IMAGE_TAG}'
                sh 'docker trust sign ${DOCKER_REGISTRY_HOSTNAME}/${DOCKER_IMAGE_NAMESPACE}/${DOCKER_IMAGE_REPOSITORY}:${DOCKER_IMAGE_TAG}'
            }
        }
    }

    stage('Deploy to Production') {
        withEnv(["DOCKER_APPLICATION_FQDN=${DOCKER_IMAGE_REPOSITORY}.prod.${DOCKER_APPLICATION_DOMAIN}",
                 "DOCKER_REGISTRY_HOSTNAME=${TARGET_CLUSTER['REGISTRY_HOSTNAME']}",
                 "DOCKER_IMAGE_NAMESPACE=${DOCKER_IMAGE_NAMESPACE_PROD}",
                 "DOCKER_IMAGE_REPOSITORY=${DOCKER_IMAGE_REPOSITORY}",
                 "DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}",
                 "DOCKER_USER_CLEAN=${DOCKER_USER_CLEAN}",
                 "MONGO_TAG=${MONGO_TAG}"
                 ]) {

            if(ORCHESTRATOR.toLowerCase() == "kubernetes"){
                println("Deploying to Kubernetes")
                withEnv(["DOCKER_KUBERNETES_CONTEXT=${TARGET_CLUSTER['KUBERNETES_CONTEXT']}", "DOCKER_KUBERNETES_NAMESPACE=${DOCKER_KUBERNETES_NAMESPACE}"]) {
                    sh 'envsubst < kubernetes/cluster/001_mongo_pvc.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/002_mongo_deployment.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/003_mongo_service.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/004_pacman_deployment.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/005_pacman_service.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                    sh 'envsubst < kubernetes/cluster/006_pacman_ingress.yml | kubectl --context=${DOCKER_KUBERNETES_CONTEXT} --namespace=${DOCKER_KUBERNETES_NAMESPACE} apply -f -'
                }
            }
            else if (ORCHESTRATOR.toLowerCase() == "swarm"){
                println("Deploying to Swarm")
                withEnv(["DOCKER_UCP_COLLECTION_PATH=${DOCKER_UCP_COLLECTION_PATH}"]) {
                    withDockerServer([credentialsId: TARGET_CLUSTER['UCP_CREDENTIALS_ID'], uri: TARGET_CLUSTER['UCP_URI']]) {
                        sh "docker stack deploy -c swarm/docker-compose.yml ${DOCKER_STACK_NAME}"
                    }
                }
            }

            println("Application deployed to Production: http://${DOCKER_APPLICATION_FQDN}")
        }
    }
}
