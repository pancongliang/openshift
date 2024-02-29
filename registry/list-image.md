### List all images in docker registry
```
#!/bin/bash
# Set variables
export REGISTRY_URL='docker.registry.example.com:5000'
export REGISTRY_ID="admin"
export REGISTRY_PW="redhat"

export ROX_API_TOKEN="${ROX_API_TOKEN}"
export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443


# Get all repositories
REPOSITORIES=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/_catalog" | jq -r '.repositories  []')

# Iterate over each repository, get tags or hashes
for REPOSITORY in $REPOSITORIES
do
    # Try to get tags
    TAGS=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/$REPOSITORY/tags/list" | jq -r '.tags  []' 2>/dev/null || echo "latest")

    # If no tags, get digest
    if [ "$TAGS" == "latest" ]; then
        DIGEST=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/$REPOSITORY/manifests/latest" | jq -r '.config.digest')
        IMAGE_URI="$REGISTRY_URL/$REPOSITORY@$DIGEST"
    elif [ -n "$TAGS" ] && [ "$TAGS" != "null" ]; then
        # Output image URI with tags
        for TAG in $TAGS
        do
            IMAGE_URI="$REGISTRY_URL/$REPOSITORY:$TAG"
            echo "Image URI: $IMAGE_URI"
        done
    fi
done
```
  
### List all images in quay registry(public repositories)
```
Create OAuth access token
1.Log in to Red Hat Quay and select your Organization (or create a new one).
2.Select the Applications icon from the left navigation.
3.Select Create New Application and give the new application a name when prompted.
4.Select the new application.
5.Select Generate Token from the left navigation.
6.Select the checkboxes to set the scope of the token and select Generate Access Token.
7.Review the permissions you are allowing and select Authorize Application to approve it.
8.Copy the newly generated token to use to access the API.
```
```
#!/bin/bash
export USER_TOKEN="hSMLaKaCMUS99VCbAkUbTM0k2oVkHxbDG36EDtei"
export QUAY_URL='https://mirror.registry.example.com:8443'

# View public repositories in the registry and retrieve namespace and name fields
REPOSITORIES=$(curl -ks -H "Authorization: Bearer ${USER_TOKEN}" "${QUAY_URL}/api/v1/repository?public=true")

# Extract namespace and repository fields
echo "$REPOSITORIES" | jq -r '.repositories | map(select(.namespace != null and .name != null)) | .[] | "\(.namespace) \(.name)"' | while read -r NS   REPO; do
  TAGS=$(curl -ks -H "Authorization: Bearer ${USER_TOKEN}" "${QUAY_URL}/api/v1/repository/${NS}/${REPO}/tag/" | jq -r '.tags | map(select(.name != null)) | .[].name')
  if [ -n "$TAGS" ]; then
    for TAG in $TAGS; do
      # Print image address
      IMAGE_URI="${QUAY_URL}/${NS}/${REPO}:${TAG}"
      echo "Image URI: $IMAGE_URI"
    done
  fi
done
```
