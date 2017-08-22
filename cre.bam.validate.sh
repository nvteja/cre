#!/bin/bash

#PBS -l walltime=5:00:00,nodes=1:ppn=1
#PBS -joe .
#PBS -d .
#PBS -l vmem=20g,mem=20g

# thorough validation:
# https://gatkforums.broadinstitute.org/gatk/discussion/7571/errors-in-sam-bam-files-can-be-diagnosed-with-validatesamfile

if [ -z $bam ]
then
    bam=$1
fi

#if file is truncated, it would be the first error message in $bam.check
#uses picard wrapper from bcbio

picard ValidateSamFile I=$bam > $bam.check
