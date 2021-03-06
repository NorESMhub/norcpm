#!/bin/bash -evx
## Project:
#SBATCH --account=nn9039k
## Job name:
#SBATCH --job-name=NorCPM_analysis
#SBATCH --error=NorCPM_log_%j
#SBATCH --output=NorCPM_out_%j
## Wall time limit:
#SBATCH --time=20:30:00
#SBATCH --nodes=8
##SBATCH --ntasks=1280
###SBATCH --qos=short
###SBATCH --qos=devel
#SBATCH --exclusive
wallTime=20:30:00  ## should be same as above SBATCH --time=[DD-]HH:MM:SS
NowPWD=$PWD
## Queue info
DateNow=$(date +%s)
wallTimeSec=$(echo $wallTime | sed -E 's/(.*)-(.*):(.+):(.+)/\1*86400+\2*3600+\3*60+\4/;s/(.*):(.+):(.+)/\1*3600+\2*60+\3/;s/(.+):(.+)/\1*60+\2/' | bc)
let queEnd=$DateNow+$wallTimeSec
##

##==============================================================================
##  This script (NorCPM2) preform NorESM2 intergation and data assimulation monthly.
##  
##  Requirements:
##      NorESM2 case members created by ${NORCPM_ROOT}/baseline/create_template.sh and create_ensemble.sh
##  Usage:
##      Submit this script to queue system.
##      ex:
##          sbatch submit_reanalysis.sh
##
##  Ping-Gin.Chiu@uib.no Jul2020
##==============================================================================

## Set NorCPM root. Should be other better idea but I do not know.
NORCPM_ROOT=/cluster/projects/nn9039k/people/${USER}/NorCPM
SCRIPTPATH=${NORCPM_ROOT}/Analysis/submit_reanalysis.sh  ## for self-resubmit
SUBMIT='sbatch'

settingFile="analysis_template.sh"  ## setting file
settingFile="analysis_template_EN4.sh"  ## setting file
settingFile="analysis_template_betzy_EN4_HadISST.sh"  ## setting file
settingFile="analysis_template_EN4_betzy.sh"  ## setting file
settingFile="analysis_template_EN4_betzy_v2.sh"

## Set the day of month preform data assimulation
ASSIMULATE_DAY=15
## Default process
TEST=0         ## only run 2 cycle if set to 1
SKIPASSIM=0    ## skip first assimlation
SKIPPROP=0     ## skip first model run

module purge
## Source settings. Maybe modify it to better usage.
if [ ! -f  ${NORCPM_ROOT}/Analysis/setting/${settingFile} ] ;then
   echo " This script submit a reanalysis.
The specification of the run are specified in a input file that must be placed 
in the setting folder and given as argument
usage : sbatch submit_reanalysis.sh "
   echo "The following setting file does not exist, we quit"
   echo "${NORCPM_ROOT}/Analysis/setting/${settingFile}"
   exit 1
fi
echo "We use file setting file ${settingFile}"
source "${NORCPM_ROOT}/Analysis/setting/${settingFile}"

## Source environment 
if [ ! -f  ${NORCPM_ROOT}/Analysis/env/env.${MACH} ] ;then
   echo " This script submit a reanalysis.
The machine setting is not available.
usage : sbatch submit_reanalysis.sh "
   echo "The following machine setting does not exist, we quit"
   echo "${NORCPM_ROOT}/Analysis/env/env.${MACH}"
   exit 1
fi
source ${NORCPM_ROOT}/Analysis/env/env.${MACH}

for i in `seq -w 001 $ENSSIZE` ; do
if [ ! -d  ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem${i} ] ;then
    echo "Members need be start with 001 and continuous id"
    echo "${NORCPM_CASEDIR}/${NORCPM_CASE}_mem${i}  does not exist."
    exit 1
fi
done
## Assimulation with full field or anomaly field
if  (( ${ANOMALYASSIM} ))  ; then
    fforano=anom
else
    fforano=ff
fi

## Increase stack size
ulimit -s unlimited

## Prepare work directory
ANALYSIS_DIRNAME='ANALYSIS'
RESULT_DIRNAME='RESULT'
mkdir -p ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}
#### Copy execuable binaries.
##### enssave
cp -f ${WORKSHARED}/bin/ensave ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/
cp -f ${WORKSHARED}/bin/prep_obs_${fforano}_V${EnKF_Version} ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/prep_obs
##### EnKF
cp -f ${WORKSHARED}/bin/EnKF_tp_${fforano}_V${EnKF_Version} ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/EnKF
                            
#cp -f ${WORKSHARED}/bin/EnKF_${grid_type}_${fforano}_V${EnKF_Version} ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/EnKF
##### micom_ensemble_init
cp -f ${WORKSHARED}/bin/micom_ensemble_init_${RES} ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/micom_ensemble_init
##### grid.nc
ln -sf  $GRIDPATH ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/

## ALL_OCN_NTASK = OCN_NTASK * ENSSIZE
#### Do not edit it.
OCN_NTASK=63 ## depended on dimension.F complied with micom_ensemble_init 
ALL_OCN_NTASK=$(echo "$OCN_NTASK * $ENSSIZE"|bc)

## Check present model restart date
NOWDATE=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem001/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc/\1/')
    short_start_date=`echo $NOWDATE | cut -c1-10`
    STARTMONTH=`echo $NOWDATE | cut -c6-7`
    STARTYEAR=`echo $NOWDATE | cut -c1-4` 
    STARTDAY=`echo $NOWDATE | cut -c9-10` 

## Intergation to day of data assimulation.
if [ "${STARTDAY}" -ne ${ASSIMULATE_DAY} ] ; then
    ## Check how many days need be run.
    if [ "${STARTDAY}" -gt ${ASSIMULATE_DAY} ] ; then
        ## need run to next month, not ready yet
        echo "Please check restart day: ${STARTDAY}, should be ${ASSIMULATE_DAY}"
        exit 1
    else
        let runNDay=${ASSIMULATE_DAY}-${STARTDAY}
    fi
    ## set run time and update namelists
    for i in $(seq -w 001 $ENSSIZE); do
        cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem${i}/
        ./xmlchange STOP_N=$runNDay
        ./xmlchange STOP_OPTION=nday
        ./xmlchange CONTINUE_RUN=true  ## need to check for continue run or not.
        ./preview_namelists 
    done
    ## run member001, which also run other members
    module purge
    echo "Intergate $runNDay day for assimulation."
    cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem001/
    ./.case.run
    wait
    source ${NORCPM_ROOT}/Analysis/env/env.${MACH}
    if [ $? != 0 ]; then
        echo 'Intergate one month failed, exit...'
        exit 1
    fi
    NOWDATE=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem001/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc/\1/')
        short_start_date=`echo $NOWDATE | cut -c1-10`
        STARTMONTH=`echo $NOWDATE | cut -c6-7`
        STARTYEAR=`echo $NOWDATE | cut -c1-4` 
        STARTDAY=`echo $NOWDATE | cut -c9-10` 
fi


## Do data assimulation and intergation 1 month, until ENDYEAR+1
ncycle=0
while true ;do
    loopStart=$(date +%s)
    NOWDATE=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem001/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc/\1/')
    mm=`echo $NOWDATE | cut -c6-7`
    yr=`echo $NOWDATE | cut -c1-4` 
    day=`echo $NOWDATE | cut -c9-10` 
    if [ $yr -gt $ENDYEAR ] ; then
        echo "================  Run done at $yr $mm"
        exit 0
    fi

    if [ $SKIPASSIM -eq 0 ] || [ ! -d "${NORCPM_RUNDIR}/${RESULT_DIRNAME}"  ] ;then  ## not skip first data assimulation
        echo "Data assimulation at $yr $mm"
        cd ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/

        ## Link forecast data
        ${WORKSHARED}/Script/Link_forecast_nocopy_V${EnKF_Version}.sh ${yr} ${mm}

        for iobs in ${!OBSLIST[*]};
        do
            OBSTYPE=${OBSLIST[$iobs]}
            PRODUCER=${PRODUCERLIST[$iobs]}
            MONTHLY=${MONTHLY_ANOM[$iobs]}
            REF_PERIOD=${REF_PERIODLIST[$iobs]}
            COMB_ASSIM=${COMBINE_ASSIM[$iobs]}    #sequential/joint observation assim 
            obsfile="${WORKSHARED}/Obs/${OBSTYPE}/${PRODUCER}/${yr}_${mm}.nc"
            test -f "$obsfile" && ln -sf "$obsfile" ./  || { echo "${obsfile} not exist, we quit" ; exit 1 ; }
            ## Uncertainty(?) Representive error file
            uncfile=${WORKSHARED}/Input/NorESM/${RES}/${PRODUCER}/${RES}_${OBSTYPE}_obs_unc_${fforano}.nc
            test -f "$uncfile" && ln -sf "$uncfile" ./obs_unc_${OBSTYPE}.nc

            if (( ${ANOMALYASSIM} )) ; then
                if (( ${MONTHLY} )) ; then ## monthly anomaly or yearly
                    meanobs="${WORKSHARED}/Obs/${OBSTYPE}/${PRODUCER}/${OBSTYPE}_avg_${mm}-${REF_PERIOD}.nc"
                    test -f ${meanobs} && ln -sf ${meanobs} mean_obs.nc || { echo "Error ${meanobs} missing, we quit" ; exit 1 ; }
                    if ((${ANOM_CPL})) ; then
                        anomcpl="${WORKSHARED}/Input/NorESM/${RES}/Anom-cpl-average${mm}-${REF_PERIOD}.nc"
                        test -f "${anomcpl}" && ln -sf "${anomcpl}" mean_mod.nc || { echo "Error ${anomcpl} missing, we quit" ; exit 1 ; }
                    else
                        avgcpl="${WORKSHARED}/Input/NorESM/${RES}/Free-average${mm}-${REF_PERIOD}.nc"
                        test -f "${avgcpl}" && ln -sf "${avgcpl}" mean_mod.nc || { echo "Error ${avgcpl} missing, we quit" ; exit 1 ; }
                    fi # ${ANOM_CPL}
                else
                    meanobs="${WORKSHARED}/Obs/${OBSTYPE}/${PRODUCER}/${OBSTYPE}_avg_${REF_PERIOD}.nc"
                    test -f "${meanobs}" && ln -sf "${meanobs}" mean_obs.nc || { echo "Error ${meanobs} missing, we quit" ; exit 1 ; }
                    if ((${ANOM_CPL})) ; then
                        anomcpl="${WORKSHARED}/Input/NorESM/${RES}/Anom-cpl-average${REF_PERIOD}.nc "
                        test -f "${anomcpl}" && ln -sf "${anomcpl}" mean_mod.nc || { echo "Error ${anomcpl} missing, we quit" ; exit 1 ; }
                    else
                        avgcpl="${WORKSHARED}/Input/NorESM/${RES}/Free-average${REF_PERIOD}.nc"
                        test -f "${avgcpl}" && ln -sf "${avgcpl}" mean_mod.nc || { echo "Error ${avgcpl} missing, we quit" ; exit 1 ; }
                    fi # ${ANOM_CPL}
                fi # ${MONTHLY}
            fi # ${ANOMALYASSIM}

            ### Prepare obs data
            template=${WORKSHARED}/Input/EnKF/infile.data.${OBSTYPE}.${PRODUCER}
            sed -e "s/yyyy/${yr}/" -e "s/mm/${mm}/" "$template" > infile.data
            ./prep_obs || { echo "Error, prep_obs failed, we quit" ; exit 1 ; }
            mv observations.uf observations.uf_${OBSTYPE}.${PRODUCER}

            if (( ${COMB_ASSIM} )) ; then #do assimilation
                ## Do not know what is it... # let EnKF_CNT=EnKF_CNT+1
                EnKF_CNT=1
                cat observations.uf_* > observations.uf
                rm -f observations.uf_*
                # only pbs_enkf.sh_V1_mal adapted to FRAM
                sed  -e "s/NENS/${ENSSIZE}/g" -e "s/C.A.S.E.D.I.R/${CASEDIR}/" "${WORKSHARED}/Script/pbs_enkf.sh_V${EnKF_Version}_mal" > pbs_enkf.sh
                chmod 755 pbs_enkf.sh
                cp -f ${WORKSHARED}/Input/EnKF/analysisfields_V${EnKF_Version}_${EnKF_CNT}.in analysisfields.in
                sed -e "s/XXX/${RFACTOR}/" "${WORKSHARED}/Input/EnKF/enkf.prm_V${EnKF_Version}_${EnKF_CNT}" > enkf.prm
                sed -i s/"enssize =".*/"enssize = "${ENSSIZE}/g enkf.prm
                #launch EnKF
                set -e 
                time ./pbs_enkf.sh
                set +e
                ## Check output
                cd ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}
                ans=`diff forecast_avg.nc analysis_avg.nc`
                if [ -z "${ans}" ] ; then
                    echo "There has been no update, we quit!!"
                    exit 1
                fi
                mv enkf_diag.nc enkf_diag_${EnKF_CNT}.nc
                mv analysis_avg.nc analysis_avg_${EnKF_CNT}.nc
                mv forecast_avg.nc forecast_avg_${EnKF_CNT}.nc
                mv tmpX5.uf tmpX5_${EnKF_CNT}.uf
                echo 'Finished with EnKF; call number :' $EnKF_CNT
            fi # ${COMB_ASSIM}
        done # iobs, loop along OBS

        ## Move to RESULT
        mkdir -p  ${NORCPM_RUNDIR}/${RESULT_DIRNAME} || { echo "Could not create RESULT dir" ; exit 1 ; }
        mkdir -p  ${NORCPM_RUNDIR}/${RESULT_DIRNAME}/${yr}_${mm} || { echo "Could not create RESULT/${yr}_${mm}" ; exit 1 ; }

        cd ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/
        mv enkf_diag_*.nc analysis_avg_*.nc forecast_avg_*.nc observations-*.nc tmpX5_*.uf ${NORCPM_RUNDIR}/${RESULT_DIRNAME}/${yr}_${mm}
        rm -f FINITO
        echo 'Finished all EnKF; now post processing'

        ## apply result to restart file with micom_ensemble_init
        cd ${NORCPM_RUNDIR}/${ANALYSIS_DIRNAME}/
        echo Try to run micom_ensemble_init...
        for i in {1..10}; do
            echo run micom_ensemble_init $i
            mpirun -n ${ALL_OCN_NTASK} ./micom_ensemble_init ${ENSSIZE} && break || { echo "micom_ensemble_init error, retry." ; }
        done
        ##mpirun -n ${ALL_OCN_NTASK} ./micom_ensemble_init ${ENSSIZE} || { echo "micom_ensemble_init error, exit..." ; exit 1 ; }
        mpirun -n ${ENSSIZE} ./ensave forecast ${ENSSIZE} || { echo "ensave error, exit..." ; exit 1 ; }
        wait

        mv forecast_avg.nc ${WORKDIR}/${CASEDIR}/RESULT/${yr}_${mm}/fix_analysis_avg.nc
        ans=`diff ${WORKDIR}/${CASEDIR}/RESULT/${yr}_${mm}/fix_analysis_avg.nc ${WORKDIR}/${CASEDIR}/RESULT/${yr}_${mm}/analysis_avg_${EnKF_CNT}.nc`
        if [ -z "${ans}" ] ; then
            echo "There has been no fix update, we quit!!"
            echo "Delete FINITO"
            rm -f FINITO
            exit 1;
        fi

        #Do some clean up
        rm -f  forecast???.nc forecast_ice???.nc aiceold???.nc viceold???.nc
        rm -f observations.uf enkf.prm* infile.data* mask.nc mask_ice.nc
        echo 'Finished with Assim post-processing'
        #every pair month we reduced rfactor by 1
        if (( $mm % 2 == 0 )) ; then
           let RFACTOR=RFACTOR-1
           test $RFACTOR -lt 1 && RFACTOR=1
        fi
    else
        SKIPASSIM=0
    fi  ## SKIPASSIM


    if [ $SKIPPROP -eq 0 ];then  ## not skip first model run
        ## Integrate NorESM for a month
        for mem in `seq -w 001 $ENSSIZE` ; do ## set run 1 month
            cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem${mem}/
            ./xmlchange STOP_N=1
            ./xmlchange STOP_OPTION=nmonth
            ./xmlchange CONTINUE_RUN=True
            ./preview_namelists > log.preview_namelists
        done
        wait
        #### Run model
        echo 'Intergate one month.'
        NOWDATE=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem001/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc */\1/')
        cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem001/
        module purge
        ./.case.run
        wait
        source ${NORCPM_ROOT}/Analysis/env/env.${MACH}
        NEWDATE=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem001/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc */\1/')

        if [ $NOWDATE = $NEWDATE ]; then
            echo 'Intergate one month failed, exit...'
            exit 1
        fi
        MEMDATE_WRONG=''
        for mem in `seq -w 001 $ENSSIZE` ; do
            NEWDATE_MEM=$(cat ${NORCPM_RUNDIR}/${NORCPM_CASE}_mem${mem}/run/rpointer.ocn| sed 's/.*\.r\.\(....-..-..-.....\)\.nc */\1/')
            if [ $NEWDATE != $NEWDATE_MEM ]; then
                MEMDATE_WRONG="${MEMDATE_WRONG}${NORCPM_CASE}_mem${mem}=${NEWDATE_MEM} "
            fi
            if [ ! -z "${MEMDATE_WRONG}" ];then
                echo 'Intergate one month failed, not all members consistant, exit...'
                echo "${MEMDATE_WRONG}"
                exit 1
            fi
        done
        echo 'Intergate one month done.'
        #### short term archiving
        #echo 'Archiving.'
        #for mem in `seq -w 001 $ENSSIZE` ; do
            #cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem${mem}/
            #./case.st_archive &
        #done
        ###### NorCPM2 modified case.run to submit st_archive for members other than 001.
        ###### So only mem001 need st_archive.
        #cd ${NORCPM_CASEDIR}/${NORCPM_CASE}_mem001/
        #./case.st_archive 
        #wait
        #echo 'Archiving done.'
    else
        SKIPPROP=0
    fi

    loopEnd=$(date +%s)
    let looptime=$loopEnd-$loopStart
    ## check rest time to run next loop, or self submit and end. 
    let loopNextEnd=$looptime+$(date +%s)
    let ncycle=$ncycle+1

    if [ $TEST -ge 1 ] && [ $ncycle -ge 2 ];then
        echo "This is the second assim cycle everything has run smoothly"
        echo "To run the full reanalysis, turn off the TEST flag in setting/personal_setting.sh"
        exit 1;
    fi

    if [ $queEnd -gt $loopNextEnd ] ; then ## still have time to finish next loop
        echo "This round cost $looptime sec. Start next round"
        continue
    else
        echo "Submit myself and end this round."
        module purge
        cd "$NowPWD"
        ${SUBMIT} "${SCRIPTPATH}"
        exit 0
    fi
done

