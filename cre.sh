#!/bin/bash

####################################################################################################
#   keeps only important files from bcbio run: qc, vcf, gemini, bam
#   creates csv report for small variants
#   keeps bam files for new samples
#   generates report

#   parameters:
# 	family = [family_id] (=project=case=folder_name,main result file should be family-ensemble.db,=project)
# 	cleanup= [0|1] default = 0
# 	make_report=[0|1] default = 1
# 	type = [ wes.regular (default) | wes.synonymous | wes.fast | rnaseq | wgs ]
####################################################################################################

#PBS -l walltime=20:00:00,nodes=1:ppn=1
#PBS -joe .
#PBS -d .
#PBS -l vmem=20g,mem=20g

# cleanup is different for wes.fast template - don't remove gatk db
function f_cleanup
{

    # better to look for project-summary than hardcode the year
    # keep bam files for new samples
    
    if [ -z $family ] 
    then
	echo "Project (family) folder does not exist. Exiting"
	exit 1
    fi
    
    cd $family
    result_dir=`find final -name project-summary.yaml | sed s/"\/project-summary.yaml"//`
    
    echo $result_dir
    
    if [ -d $result_dir ]
    then
	mv $result_dir/* .
	mv final/*/*.bam .
	mv final/*/*.bai .
	# keep validation picture
	mv final/*/*.png .
	
	# keep sv calls
	if [ "$type" == "wgs" ]
	then
	    mv final sv
	fi
	
        rm -rf final/
	rm -rf work/
    
	#proceed only if there is a result dir

        #don't remove input files for new projects
	#rm -rf input/

        #rename bam files to match sample names
	for f in *ready.bam;do mv $f `echo $f | sed s/"-ready"//`;done;
        for f in *ready.bam.bai;do mv $f `echo $f | sed s/"-ready"//`;done;

	#make bam files read only
        for f in *.bam;do chmod 444 $f;done;

	#calculate md5 sums
        for f in *.bam;do md5sum $f > $f.md5;done;

	#validate bam files
        for f in *.bam;do	cre.bam.validate.sh $f;done;
    
	if [ "$type" == "wes.fast" ] || [ "$type" == "wgs" ]
	then
	    ln -s ${family}-gatk-haplotype.db ${family}-ensemble.db
	    ln -s ${family}-gatk-haplotype-annotated-decomposed.vcf.gz ${family}-ensemble-annotated-decomposed.vcf.gz
	    ln -s ${family}-gatk-haplotype-annotated-decomposed.vcf.gz.tbi ${family}-ensemble-annotated-decomposed.vcf.gz.tbi
	else
	    # we don't need gemini databases for particular calling algorythms
	    rm ${family}-freebayes.db
	    rm ${family}-gatk-haplotype.db
	    rm ${family}-samtools.db
	    rm ${family}-platypus.db
	fi
    fi
    cd ..
}

function f_make_report
{
    cd $family

    if [ "$type" == "rnaseq" ]
    then
	export depth_threshold=5
	export severity_filter=ALL
    elif [ "$type" == "wes.synonymous" ] || [ "$type" == "wgs" ]
    then
	export depth_threshold=10
	export severity_filter=ALL
    else
	export depth_threshold=10
	export severity_filter=HIGHMED
    fi

    cre.gemini2txt.sh ${family}-ensemble.db $depth_threshold $severity_filter
    cre.gemini_variant_impacts.sh ${family}-ensemble.db $depth_threshold $severity_filter

    for f in *.vcf.gz;
    do
	tabix $f;
    done

    # report filtered vcf for import in phenotips
    # note that if there is a multiallelic SNP, with one rare allele and one frequent one, both will be reported in the VCF,
    # and just a rare one in the excel report
    cat ${family}-ensemble.db.txt | cut -f 23,24  | sed 1d | sed s/chr// | sort -k1,1 -k2,2n > ${family}-ensemble.db.txt.positions
    # this may produce duplicate records if two positions from positions file overlap with a variant 
    # (there are 2 positions and 2 overlapping variants, first reported twice)
    bgzip -d -c ${family}-ensemble-annotated-decomposed.vcf.gz | grep "^#" > $family.tmp.vcf
    bcftools view -R ${family}-ensemble.db.txt.positions ${family}-ensemble-annotated-decomposed.vcf.gz | grep -v "^#" | sort | uniq >>  ${family}.tmp.vcf
    bgzip -f $family.tmp.vcf
    tabix $family.tmp.vcf.gz
    bcftools sort -o $family.vcf.gz -Oz $family.tmp.vcf.gz
    tabix $family.vcf.gz
    rm $family.tmp.vcf.gz $family.tmp.vcf.gz.tbi

    #individual vcfs for uploading to phenome central
    vcf.split_multi.sh $family.vcf.gz

    reference=$(readlink -f `which bcbio_nextgen.py`)
    reference=`echo $reference | sed s/"anaconda\/bin\/bcbio_nextgen.py"/"genomes\/Hsapiens\/GRCh37\/seq\/GRCh37.fa"/`
    
    echo $reference

    vcf.ensemble.getCALLERS.sh $family.vcf.gz $reference

    #decompose first for the old version of bcbio!
    #gemini.decompose.sh ${family}-freebayes.vcf.gz
    vcf.freebayes.getAO.sh ${family}-freebayes-annotated-decomposed.vcf.gz $reference

    #gemini.decompose.sh ${family}-gatk-haplotype.vcf.gz
    vcf.gatk.get_depth.sh ${family}-gatk-haplotype-annotated-decomposed.vcf.gz $reference

    #gemini.decompose.sh ${family}-platypus.vcf.gz
    vcf.platypus.getNV.sh ${family}-platypus-annotated-decomposed.vcf.gz $reference

    cd ..

    # using Rscript from bcbio
    Rscript ~/cre/cre.R $family
    
    cd $family
    #rm $family.create_report.csv $family.merge_reports.csv
    cd ..
}

if [ -z $family ]
then
    family=$1
fi

echo $family

if [ -z "$rnaseq" ]
then
    rnaseq=0
fi

export depth_threshold=10

if [ "$type" == "rnaseq" ]
then
    export depth_threshold=5
    export severity_filter=ALL
fi

#no cleanup by default
if [ -z $cleanup ]
then
    cleanup=0
fi

if [ $cleanup -eq 1 ]
then
    f_cleanup
fi

#make report by default
if [ -z $make_report ]
then
    make_report=1
fi 

if [ $make_report -eq 1 ]
then
    f_make_report
fi
