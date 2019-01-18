
pipeline
{
    agent any

    stages
    {
        stage( 'Build and Push Image' )
        {
            steps
            {
                script
                {
                    docker.withRegistry('', 'safe.docker.login.id')
                    {
                        def customImage = docker.build("devops4me/rabbitmq-3.7:${env.BUILD_ID}")
                        customImage.push("${env.BUILD_NUMBER}")
                        customImage.push("latest")
                    }
                }
            }
        }
    }
}
