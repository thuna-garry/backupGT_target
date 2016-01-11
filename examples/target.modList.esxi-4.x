#! /bin/sh 

###############################################################
# script to create a list of modules to be backed up
###############################################################
. ${0%/*}/target.conf
. ${0%/*}/target.modlist.any

MOD_LIST=$MOD_LIST_PATH.$$


############################################################################
# local modules
############################################################################
localModules () {
    local hostName=`hostname -f`
    local origHost=${hostName%.*.*}
    cat <<-__EOF__ >>$MOD_LIST
	opt		auto=true method=rsync origHost=$origHost path=/opt                                          key=$((++kc))
	dotSsh		auto=true method=rsync origHost=$origHost path=/.ssh                                         key=$((++kc))
	disks		auto=true method=rsync origHost=$origHost path=/vmfs/volumes/datastoreLocal/_disks           key=$((++kc))
	templates	auto=true method=rsync origHost=$origHost path=/vmfs/volumes/datastoreLocal/_templates       key=$((++kc))
	incomminBackups	auto=true method=rsync origHost=$origHost path=/vmfs/volumes/datastoreLocal/incommingBackups key=$((++kc))
	__EOF__
}

                            
############################################################################
# vm guests
############################################################################
#utcWindowStart=`printf "%06d" $(( (220000 +  60000 + 240000) % 240000 ))`
#utcWindowEnd=`  printf "%06d" $(( ( 30000 +  60000 + 240000) % 240000 ))`

vmGuests () {
    vm_guest_list | while read vmID vmName vmxFile vmxPath vmxDir; do
    
        # include/exclude/segregate specific guests
        case $vmName in
            * )
                # write the modList entry
                {   printf "%s\t" "$vmName"
                    printf "%s "  "auto=true"
                    printf "%s "  "method=rsync"
                    printf "%s "  "path=/vmfs/volumes"
                    printf "%s "  "key=$((++kc))"
                    echo ""
                } >>$MOD_LIST

                cp "$vmxPath" "$vmxPath.save"
                
                # gather the files to be included
                {
                    echo $vmxPath.save
                    find $vmxDir -name '*.vmsd'
                    find $vmxDir -name '*.vmsn'
                    find $vmxDir -name '*.vmxf'
                    find $vmxDir -name '*-aux.xml'
                    vm_getAllVmdk "$vmxPath"
                } | sed -e "s:^/vmfs/volumes::"   \
                  | while read f; do
                        #for each file need to include each parent directory
                        while [ "$f" != "//" ]; do
                            echo "+ $f"
                            f=`dirname $f`/
                        done
                    done   \
                  | sort | uniq  \
                  > $RSYNC_INC_PATH_PREFIX.$vmName
                echo '- **' >> $RSYNC_INC_PATH_PREFIX.$vmName
                ;;
        esac
                
        # write the procs file for this module/vmGuest
        writeVmProcs $vmName
    done
}


writeVmProcs () {
    modName=$1
    cat > ${PROC_PATH_PREFIX}.${modName} <<"__EOF__"

    createRsyncd_includes () {
        local requestModule="$1"
        echo "include from = $RSYNC_INC_PATH_PREFIX.$requestModule"
    }

    module_rsync_init() {
        local requestModule="$1"
        trap 'vm_snapshot_remove "$requestModule"' 0 1 2 3 4 15
        vm_snapshot_create "$requestModule"
    }

    module_rsync_fini() {
        local requestModule="$1"
        vm_snapshot_remove "$requestModule"
        trap - 0 1 2 3 4 15
    }

    module_tar_init() {
        local requestModule="$1"
        trap 'vm_snapshot_remove "$requestModule"' 0 1 2 3 4 15
        vm_snapshot_create "$requestModule"
    }

    module_tar_fini() {
        local requestModule="$1"
        vm_snapshot_remove "$requestModule"
        trap - 0 1 2 3 4 15
    }

__EOF__
}



###############################################################
# main
###############################################################
kc=0    #key count

localModules;  kc=`wc -l $MOD_LIST | awk '{print $1}'`
vmGuests;      kc=`wc -l $MOD_LIST | awk '{print $1}'`

mv $MOD_LIST $MOD_LIST_PATH
cat $MOD_LIST_PATH

