#!/usr/bin/env nextflow

params.input = './analysis'
params.output = './analysis'

params.bams="$params.input/*.bam"
params.design="$params.input/design.txt"

params.genome="/project/shared/bicf_workflow_ref/GRCh38"
params.targetpanel="$params.genome/UTSWV2.bed"
params.cancer="detect"
params.callsvs="detect"

dbsnp_file="$params.genome/dbSnp.vcf.gz"
indel="$params.genome/GoldIndels.vcf.gz"
cosmic="$params.genome/cosmic.vcf.gz"
reffa=file("$params.genome/genome.fa")

design_file = file(params.design)
bams=file(params.bams)

dbsnp=file(dbsnp_file)
knownindel=file(indel)
index_path = file(params.genome)
capture_bed = file(params.targetpanel)

snpeff_vers = 'GRCh38.86';

def fileMap = [:]

bams.each {
    final fileName = it.getFileName().toString()
    prefix = fileName.lastIndexOf('/')
    fileMap[fileName] = it
}

def oribam = []
def tarbam = []
new File(params.design).withReader { reader ->
    def hline = reader.readLine()
    def header = hline.split("\t")
    sidx = header.findIndexOf{it == 'FamilyID'};
    tidx = header.findIndexOf{it == 'SampleID'};
    oneidx = header.findIndexOf{it == 'BAM'};
    taridx = header.findIndexOf{it == 'FinalBAM'};
    if (sidx == -1) {
       sidx = tidx
       }
    while (line = reader.readLine()) {
    	   def row = line.split("\t")
	   if (fileMap.get(row[oneidx]) != null) {
	      oribam << tuple(row[tidx],fileMap.get(row[oneidx]))
	      tarbam << tuple(row[sidx],fileMap.get(row[taridx]))
	   }
	  
} 
}

if( ! oribam) { error "Didn't match any input files with entries in the design file" }
if( ! tarbam) { error "Didn't match any input files with entries in the design file" }

process indexoribams {
  errorStrategy 'ignore'
  input:
  set tid,file(tumor) from oribam
  output:
  set tid,file(tumor),file("${tumor}.bai") into svbam
  set tid,file(tumor),file("${tumor}.bai") into cnvbam
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/alignment/indexbams.sh 
  """
}

process indexbams {
  input:
  set tid,file(tumor) from tarbam
  output:
  set tid,file(tumor),file("${tumor}.bai") into idxbam
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/alignment/indexbams.sh 
  """
}

idxbam
   .groupTuple(by:0)		
   .into { ssbam; sambam; hsbam; platbam; strelkabam }

process cnv {
  errorStrategy 'ignore'
  publishDir "$params.output/$pair_id", mode: 'copy'
  input:
  set pair_id,file(sbam),file(sidx) from cnvbam
  output:
  file("${pair_id}.call.cns") into cnvtxt
  file("${pair_id}.cnv.pdf") into cnvpdf
  script:
  """
  source /etc/profile.d/modules.sh	
  bash $baseDir/process_scripts/variants/cnvkit.sh -u -b $sbam -p $pair_id
  """
}
 
process svcall {
  errorStrategy 'ignore'
  publishDir "$params.output/$pair_id", mode: 'copy'
  input:
  set pair_id,file(ssbam),file(ssidx) from svbam
  output:
  file("${pair_id}.delly.vcf.gz") into dellyvcf
  file("${pair_id}.sssv.sv.vcf.gz") into svvcf
  file("${pair_id}.sv.annot.vcf.gz") into svintvcf
  file("${pair_id}.sv.annot.txt") into svannot
  file("${pair_id}.sv.annot.genefusion.txt") into gfusion
  when:
  params.callsvs == "detect"
  script:
  """
  source /etc/profile.d/modules.sh	
  bash $baseDir/process_scripts/variants/svcalling.sh -b $ssbam -r $index_path -p $pair_id
  """
}

process mpileup {
  errorStrategy 'ignore'
  //publishDir "$baseDir/output", mode: 'copy'

  input:
  set subjid,file(gbam),file(gidx) from sambam
  
  output:
  set subjid,file("${subjid}.sam.vcf.gz") into samvcf
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a mpileup
  """
}
process hotspot {
  errorStrategy 'ignore'
  //publishDir "$baseDir/output", mode: 'copy'

  input:
  set subjid,file(gbam),file(gidx) from hsbam
  output:
  set subjid,file("${subjid}.hotspot.vcf.gz") into hsvcf
  when:
  params.cancer == "detect"
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a hotspot
  """
}
process speedseq {
  errorStrategy 'ignore'
  //publishDir "$baseDir/output", mode: 'copy'
  input:
  set subjid,file(gbam),file(gidx) from ssbam
  output:
  set subjid,file("${subjid}.ssvar.vcf.gz") into ssvcf
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a speedseq
  """
}
// process gatkgvcf {
//   errorStrategy 'ignore'
//   //publishDir "$baseDir/output", mode: 'copy'

//   input:
//   set subjid,file(gbam),file(gidx) from gatkbam
//   output:
//   set subjid, file("${subjid}.gatk.vcf.gz") into gatkvcf
//   script:
//   """
//   source /etc/profile.d/modules.sh
//   bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a gatk
//   """
// }

process strelka2 {
  errorStrategy 'ignore'
  //publishDir "$baseDir/output", mode: 'copy'

  input:
  set subjid,file(gbam),file(gidx) from strelkabam
  output:
  set subjid,file("${subjid}.strelka2.vcf.gz") into strelkavcf
  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a strelka2
  """
}

process platypus {
  errorStrategy 'ignore'
  //publishDir "$params.output", mode: 'copy'

  input:
  set subjid,file(gbam),file(gidx) from platbam

  output:
  set subjid,file("${subjid}.platypus.vcf.gz") into platvcf

  script:
  """
  source /etc/profile.d/modules.sh
  bash $baseDir/process_scripts/variants/germline_vc.sh -r $index_path -p $subjid -a platypus
  """
}

Channel
  .empty()
  .mix(ssvcf,strelkavcf,samvcf,platvcf,hsvcf)
  .groupTuple(by:0)
  .into { vcflist}

process integrate {
  errorStrategy 'ignore'
  publishDir "$params.output", mode: 'copy'
  input:
  set subjid,file(vcf) from vcflist

  output:
  set subjid,file("${subjid}.union.vcf.gz") into union
  file("${subjid}.annot.vcf.gz") into annotvcf
  script:
  """
  bash $baseDir/process_scripts/variants/union.sh -r $index_path -p $subjid
  bash $baseDir/process_scripts/variants/annotvcf.sh -p $subjid -r $index_path -v $unionvcf
  """
}