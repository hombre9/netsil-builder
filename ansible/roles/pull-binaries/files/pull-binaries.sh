#!/bin/bash

# Pull images, compress, and construct image-service index
cd /opt/netsil/latest/apps/build/specs
for app in *.json
do
    # Pull docker images
    image=$(jq --raw-output < ${app} 'select(.container.docker.image != null) .container.docker.image')
    if [[ -n ${image} ]] ; then
        echo "Pulling image ${image}"
        docker pull ${image}
        if [[ $? != 0 ]] ; then
            echo "Docker pull failed. Exiting build."
            exit 1
        fi
    fi
done


### NOTE: This section is likely deprecated. Evaluate and remove later if so. ###
asset_dir=/opt/netsil/latest/assets
cd /opt/netsil/latest/apps/build/config
for config in *.json
do
    # Pull asset list
    assets=$(jq --raw-output < ${config} 'select(.resource.assets.remote_uris != null) | .resource.assets.remote_uris | .[]')
    if [[ -n ${assets} ]] ; then
        # Get config id: Splits foo.config.json into foo.
        IFS='.' read -a config_id <<< "${config}"

        # Get app id
        app_id=$(jq --raw-output < /opt/netsil/latest/apps/build/specs/${config_id[0]}.json '.id')
        mkdir -p ${asset_dir}/${app_id}

        echo "Downloading assets for ${app_id}"
        for asset in ${assets[@]}
        do
            # Gets the last part of the url path, which is typically the filename
            asset_name=`basename ${asset}`
            asset_path="${asset_dir}/${app_id}/${asset_name}"
            echo "Downloading ${asset} into ${asset_path}"
            wget ${asset} -O ${asset_path}
            if [[ $? != 0 ]] ; then
                echo "Asset download failed. Exiting build."
                exit 1
            fi
        done
    fi
done
