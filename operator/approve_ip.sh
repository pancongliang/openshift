# Set the maximum number of retries
MAX_RETRIES=20
RETRY_COUNT=0
progress_started=false

# Poll until the maximum retry count is reached
while true; do
    # Find unapproved InstallPlans in the specified namespace
    INSTALLPLAN=$(oc get installplan -n "$NAMESPACE" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}')

    # If an unapproved InstallPlan is found
    if [[ -n "$INSTALLPLAN" ]]; then
        # Get the name of the first unapproved InstallPlan
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')

        # Approve the InstallPlan
        oc patch installplan "$NAME" -n "$NAMESPACE" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null
        
        # Close the progress indicator if it was started
        if [[ "$progress_started" == true ]]; then
            echo "]"
        fi

        echo "ok: [Approved install plan: $NAME in namespace $NAMESPACE]"
        break
    fi
    
    # If no unapproved InstallPlans are found, check if the maximum retry count has been reached
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [[ $RETRY_COUNT -ge $MAX_RETRIES ]]; then
        if [[ "$progress_started" == true ]]; then
            echo "]"
        fi
        echo "failed: [Max retries reached. no unapproved install plans found in $NAMESPACE]"
        break
    fi
    
    # Print progress indicator every 6 seconds
    if [[ "$progress_started" == false ]]; then
        echo -n "info: [Waiting for unapproved install plans in namespace $NAMESPACE"
        progress_started=true
    fi

    echo -n '.'
    sleep 6
done
