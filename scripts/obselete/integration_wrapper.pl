#!/usr/bin/perl -w
#integration_wrapper.pl

#Need to load modules for samtools, snpsift, and vcftools

#perl integration_wrapper.pl /project/PHG/PHG_Clinical/complete/SU16-1323

my ($month,$year) = (localtime)[4,5];
$year += 1900;
$month++;
my $date=$year.sprintf("%02s",$month);

#Determines subject name and identifies directories in given path
my ($refdir) = $ARGV[0];
my @splitPath = split(/\//, $refdir);
my $subject =$splitPath[-1];
my $prefix = $refdir."/".$subject;
my @directories = `find $refdir -type d -maxdepth 1| sed 's|$refdir/||'`;

#Identifies folders as tumor,normal,somatic or rnaseq
my ($fusion,$svcf)=("") x 2;
my $tumorid="no_tumor";
my $normalid="no_normal";
my $somaticid="no_normal";
my $rnaseqid="no_rnaseq";

foreach my $directory(@directories){
  chomp $directory;
  if($directory =~ m/_T_DNA_panel1385/){
    if($directory !~ m/_N_DNA_panel1385/){
      $tumorid=$directory;
      $svcf=$refdir."/".$tumorid."/".$tumorid.".sv.annot.txt";}}
  elsif($directory =~ m/_N_DNA_panel1385/){
    if($directory !~ m/_T_DNA_panel1385/){
      $normalid=$directory;}}
  elsif($directory =~ m/_RNA_panelrnaseq/){
      $rnaseqid=$directory;
      $fusion=$refdir."/".$rnaseqid."/".$rnaseqid.".starfusion.txt";}
}
if($tumorid ne "no_tumor" && $normalid ne "no_normal"){
  $somaticid =$tumorid."_".$normalid;
}
#Run scripts to generate final vcfs, translocations and xml output and moves them into a Philips monitored directory
#Translocations formatted file for Information Resources
#Determines the MAF of 'PASS'ing variants
if($tumorid ne "no_tumor"){
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/integrate_vcfs.pl $subject $subject $tumorid $somaticid $rnaseqid");
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/calc_tmb.pl $prefix\.utsw.vcf.gz >$prefix\.tmb.txt");
    system("cat $somaticid/$somaticid\.sequence.stats.txt $prefix\.tmb.txt >$prefix\.sequence.stats.tmb.txt")
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/convert4philips.pl $prefix\.utsw.vcf.gz");
    system("python /cm/shared/apps/crossmap/0.2.5/bin/CrossMap.py vcf /project/shared/bicf_workflow_ref/hg38ToHg19.over.chain.gz $prefix\.PASS.vcf.gz /project/apps_database/iGenomes/Homo_sapiens/UCSC/hg19/Sequence/WholeGenomeFasta/genome.fa $prefix\.PASS.hg19.vcf");
    system("bgzip $prefix\.PASS.hg19.vcf");
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/extract_greyzone.pl $prefix\.PASS.vcf.gz $rnaseqid\/$rnaseqid.fpkm.txt");
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/extract_greyzone.pl $prefix\.PASS.hg19.vcf.gz $rnaseqid\/$rnaseqid.fpkm.txt");
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/philipsCSV.pl $prefix\.PASS.tumoronly.csv $prefix\.PASS.hg19.tumoronly.csv");
    #system("cp $pefix\.vcf.gz /project/PHG/PHG_Sap/input/GenomicsFiles/");
    system("perl /project/PHG/PHG_Clinical/clinseq_workflows/scripts/integrate_translocations.pl -svcf $svcf -fusion $fusion");
    #my $philipsTranslocation = $svcf;
    #$philipsTranslocation =~ s/sv.annot.txt/translocations.txt/;
    #system("cp $philipsTranslocation /project/PHG/PHG_Sap/input/GenomicsFiles/");
    #system("ln -s /project/shared/bicf_workflow_ref/vcf2maf/.vep ~/.vep");
    system("gunzip $prefix\.PASS.vcf.gz");
    system("perl /project/shared/bicf_workflow_ref/vcf2maf/vcf2maf.pl --input $prefix\.PASS.vcf --output $prefix\.maf --species homo_sapiens --ncbi-build GRCh38 --ref-fasta /project/shared/bicf_workflow_ref/vcf2maf/.vep/homo_sapiens/87_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa --cache-version 87 --vep-path /project/shared/bicf_workflow_ref/vcf2maf/variant_effect_predictor --tumor-id $tumorid");
    system("bgzip $prefix.PASS.vcf");
  prinl OUT $final_line;
    system("python /project/PHG/PHG_Clinical/clinseq_workflows/IntellispaceDemographics/gatherdemographics.py -i $subject -u phg_workflow -p UGMP_Cl1nS3q -o /project/PHG/PHG_Sap/input/GenomicsFiles/$subject.xml");
}


