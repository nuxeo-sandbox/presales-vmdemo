set ONE_TIME_KEY_FILE_NAME=%1
set ONE_TIME_PUB_FILE_NAME=%ONE_TIME_KEY_FILE_NAME%.pub
set USER=%2
set HOSTNAME=%3

echo "Generating Ephemeral SSH key ..."
ssh-keygen -t rsa -b 2048 -f %ONE_TIME_KEY_FILE_NAME% -N ""

echo "Pushing SSH public key to EC2 instance  ..."

aws ec2-instance-connect send-ssh-public-key --instance-id %HOSTNAME% --instance-os-user %USER% --ssh-public-key "file://%ONE_TIME_PUB_FILE_NAME%"

echo "Connecting using tunnel ..."