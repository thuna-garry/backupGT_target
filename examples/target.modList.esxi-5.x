#! /bin/sh 

###############################################################
# script to create a list of modules to be backed up
###############################################################
. ${0%/*}/target.conf

#-------------------------------------------------------------------------------
# - data lines consist of two fields (moduleName, comment) separated by a tab
#
# - each comment may contain the following options
#   method          scope: all            suppliedBy: targetHost (required)
#   auto            scope: any            suppliedBy: targetHost (optional)
#   relDS           scope: zfs,zfs.rsync  suppliedBy: targetHost (required)
#   origHost        scope: rsync,tar      suppliedBy: targetHost (optional)
#   origMod         scope: rsync,tar      suppliedBy: targetHost (optional)
#   origName        scope: rsync,tar      suppliedBy: targetHost (optional)
#   key             scope: rsync,tar      suppliedBy: targetHost (optional)
#   lastSnap        scope: zfs,zfs.rsync  suppliedBy: backupServer (required)
#   utcWindowStart  scope: any            suppliedBy: targetHost (optional)
#   utcWindowEnd    scope: any            suppliedBy: targetHost (optional)
#
# - additional options unused by the backupGT.server
#   path      scope: rsync,tar      suppliedBy: targetHost (required)
#   rootDS    scope: zfs,zfs.rsync  suppliedBy: targetHost (required)
#   tmpDS     scope: zfs.rsync      suppliedBy: targetHost (required)
#-------------------------------------------------------------------------------

localTime2utc() {
    local ltime=$1
    tzoffset=`date +%z`00
    if echo "$tzoffset" | grep -q -- -; then
        # tzoffset is negative
        tzoffset=`echo $tzoffset | sed -e 's/^.//'`
        printf "%06d" $(( (10#$ltime + 10#$tzoffset + 240000) % 240000 ))
    else
        # tzoffset is positive
        tzoffset=`echo $tzoffset | sed -e 's/^.//'`
        printf "%06d" $(( (10#$ltime - 10#$tzoffset + 240000) % 240000 ))
    fi
}

MOD_LIST=$MOD_LIST_PATH.$$


############################################################################
# utility
############################################################################
getAllVmdk () {
    #BUGS: requires all virtual disks to have a .vmdk extension
    #      to ensure that copy is fully functional all disks are copied
    #        including independent disks and snapshots
    vmxPath="$1"
    vmxDir="${1%/*}"
    diskIds=` grep -iE '(scsi|ide)' "$vmxPath"  \
            | grep -i "\.fileName = .*\.vmdk"   \
            | sed 's/\..*//'                    `
    for diskId in $diskIds; do
        if grep -qi "^${diskId}\.present =.*true" "$vmxPath"; then       #device is present
            # list all vmdk files for the current diskId
            baseVmdkFile=` grep -i "^${diskId}\.fileName =" "$vmxPath"  \
                         | sed 's/^.* = *//'                            \
                         | sed 's/^"//'                                 \
                         | sed 's/"$//'                                 \
                         | sed 's/\.vmdk$//'                            \
                         | sed 's/[-][0-9][0-9][0-9][0-9][0-9][0-9]$//' `
            ls ${vmxDir}/${baseVmdkFile}-*.vmdk
            ls ${vmxDir}/${baseVmdkFile}.vmdk
        fi 
    done
}


############################################################################
# local modules
############################################################################
localModules () {
    cat <<-__EOF__ >>$MOD_LIST
	keysRoot	auto=true method=rsync origHost=esxHost1.yyc path=/etc/ssh/keys-root/
	disks		auto=true method=rsync origHost=esxHost1.yyc path=/vmfs/volumes/datastoreLocal/_disks
	templates	auto=true method=rsync origHost=esxHost1.yyc path=/vmfs/volumes/datastoreLocal/_templates
	incomminBackups	auto=true method=rsync origHost=esxHost1.yyc path=/vmfs/volumes/datastoreLocal/incommingBackups
	__EOF__
}


                            
############################################################################
# vm guests
############################################################################
vmGuests () {
    vim-cmd vmsvc/getallvms | grep ']' | while read line; do
        vmID=`   echo "$line" | awk '{print $1}' `
        vmName=` echo "$line" | sed -e 's/^[^ ]* *//'      \
                                    -e 's/ *\[.*$//'       \
                                    -e 's/ /\\ /g'         `
        vmxFile=`echo "$line" | sed -e 's/^.*] *//'           \
                                    -e 's/\.vmx  .*/\.vmx/'   \
                                    -e 's/^.*\///'            \
                                    -e 's/ /\\ /g'            `
        vmxPath=`echo "$line" | sed -e 's/^[^[]*\[/\/vmfs\/volumes\//' \
                                    -e 's/] */\//'                     \
                                    -e 's/\.vmx  .*/\.vmx/'            \
                                    -e 's/ /\\ /g'                     `
        vmxDir=${vmxPath%/*}


        # include/exclude/segregate specific guests
        case $vmName in
            generic.rsync )
                # write the modList entry
                {   printf "%s\t" "$vmName"
                    printf "%s "  "auto=true"
                    printf "%s "  "method=rsync"
                    printf "%s "  "path=$vmxDir"
                    echo ""
                } >>$MOD_LIST

                # write the rsync filter file
                cp "$vmxPath" "$vmxPath.save"
                {   echo $vmxPath.save
                    ls $vmxDir/*.vmsd
                    ls $vmxDir/*.vmxf
                    ls $vmxDir/*-aux.xml
                    getAllVmdk "$vmxPath"
                } | sed -e "s:^${vmxDir}/::"   \
                  | sed -e 's:^:+ :'   \
                  > $vmxDir/$RSYNC_FILTER_FILE
                echo '- **' >> $vmxDir/$RSYNC_FILTER_FILE

                ;;

            generic.tar ) 
                # write the modList entry
                {   printf "%s\t" "$vmName" 
                    printf "%s "  "auto=true"
                    printf "%s "  "method=tar"
                    printf "%s "  "path=$vmxDir"
                    echo ""
                } >>$MOD_LIST
        
                # write the tar include file list
                cp "$vmxPath" "$vmxPath.save"
                {   echo $vmxPath.save
                    ls $vmxDir/*.vmsd
                    ls $vmxDir/*.vmxf
                    getAllVmdk "$vmxPath"
                }  > $TAR_INC_PATH_PREFIX.$vmName
                # } | sed -e 's/ /\\\\ /g' > $TAR_INC_PATH_PREFIX.$vmName
                
                ;;

            * )
                # write the modList entry
                {   printf "%s\t" "$vmName"
                    printf "%s "  "auto=true"
                    printf "%s "  "method=rsync"
                    printf "%s "  "path=$vmxDir"
                    echo ""
                } >>$MOD_LIST

                # write the rsync filter file
                cp "$vmxPath" "$vmxPath.save"
                {   echo $vmxPath.save
                    ls $vmxDir/*.vmsd
                    ls $vmxDir/*.vmxf
                    ls $vmxDir/*-aux.xml
                    getAllVmdk "$vmxPath"
                } | sed -e "s:^${vmxDir}/::"   \
                  | sed -e 's:^:+ :'   \
                  > $vmxDir/$RSYNC_FILTER_FILE
                echo '- **' >> $vmxDir/$RSYNC_FILTER_FILE

                ;;
        esac
                
        # write the procs file for this module/vmGuest
        writeVmProcs $vmName
    done
}


writeVmProcs () {
    modName=$1
    cat > ${PROC_PATH_PREFIX}.${modName} <<"__EOF__"
    
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
localModules
vmGuests

mv $MOD_LIST $MOD_LIST_PATH
cat $MOD_LIST_PATH

