#!/usr/bin/perl -w
#extract_greyzone.pl

my $vcffile = shift @ARGV;
my $fpkmfile = shift @ARGV;
my $prefix = $vcffile;
$prefix =~ s/\.vcf.gz//;
my $input = "$vcffile" or die $!;
open OUT, ">$prefix\.tumornormal.csv" or die $!;
print OUT join(",",'Chr:Pos','ID','Gene','AminoAcid','Effect','Ref','Alt',
	       'SomaticStatus','RNASeqValidation; 1=YES; 0=NO','Gene Abundance (FPKM)','NofOne','Cosmic Disease',
	       'Cosmic Role','Tumor DNA AF','Tumor DNA Depth','Normal DNA AF','Normal DNA Depth','Tumor RNA AF',
	       'Tumor RNA Depth','StrandBias','CIVIC Gene Annotation'),"\n";

my $refdir = '/project/shared/bicf_workflow_ref/human/GRCh38/';
my %cosmic;
open OM, "<$refdir\/cosmic_census.txt" or die $!;
while (my $line = <OM>) {
    chomp($line);
    my ($gene,$tumortype,$roleincancer) = split(/\t/,$line);
    $cosmic{$gene} = $tumortype;
    $roleincancer{$gene} = $roleincancer;
}
close OM;
my %civic;
open OM, "<$refdir\/civic_GeneSummaries.tsv" or die $!;
while (my $line = <OM>) {
    chomp($line);
    my ($geneid,$url,$gene,$entrezid,$descr,$lastreview) = split(/\t/,$line);
    $descr =~ s/,/;/g;
    $civic{$gene} = $descr
}
close OM;
my %nofone;
open OM, "<$refdir\/nofone.genelist.txt" or die $!;
while (my $line = <OM>) {
  chomp($line);
  $nofone{$line} = 1;
}
close OM;
open RNACT, "<$fpkmfile" or die $!;
while (my $line = <RNACT>) {
    chomp($line);
    next if ($line =~ m/^#|Geneid|FPKM/);
    my ($ensid,$gene,$chr,$strand,$start,$end,$cov,$fpkm,$tmp) = split(/\t/,$line);
    $fpkm{$gene} = $fpkm if ($fpkm > 1);
}

open IN, "gunzip -c $input|" or die $!;
W1:while (my $line = <IN>) {
  chomp($line);
  if ($line =~ m/^#CHROM/) {
    my @header = split(/\t/,$line);
    ($chrom, $pos,$id,$ref,$alt,$score,
     $filter,$info,$format,@gtheader) = split(/\t/, $line);
  }
  if ($line =~ m/^#/) {
    #print OUT $line,"\n";
    next;
  }
  my ($chrom, $pos,$id,$ref,$alt,$score,
      $filter,$annot,$format,@gts) = split(/\t/, $line);
  next if ($ref =~ m/\./ || $alt =~ m/\./ || $alt=~ m/,X/);
  next unless ($filter eq 'PASS');
  my %hash = ();
  foreach $a (split(/;/,$annot)) {
    my ($key,$val) = split(/=/,$a);
    $val =~ s/,/\|/g if ($val);
    $hash{$key} = $val unless ($hash{$key});
  }
  $alt =~ s/,/\|/g;
  $hash{RnaSeqDP} = 0 unless $hash{RnaSeqDP};
  $hash{RnaSeqAF} = 0 unless $hash{RnaSeqAF};
  $hash{RnaSeqValidation} = 0 unless ($hash{RnaSeqValidation});
  $strandbias = $hash{SAP} if (defined($hash{SAP}));
  $strandbias = $hash{FS} if (defined($hash{FS}));
  my $somstatus = 'unk';
  $somstatus = 'Somatic' if ($hash{SS} == 2);
  $somstatus = 'Germline' if ($hash{SS} == 1);
  my $rnaexpress = 0;
  my $incosmic = 0;
  my $innofone = 0;
  my $inrole = 0;
  my $incivic = 0;
  my $aachange;
  my $genechange;
  my $effectchange;
  my $aa;
  foreach $trx (split(/,/,$hash{ANN})) {
      my ($allele,$effect,$impact,$gene,$geneid,$feature,
	  $featureid,$biotype,$rank,$codon,$aa,$pos_dna,$len_cdna,
	  $cds_pos,$cds_len,$aapos,$aalen,$distance,$err) = split(/\|/,$trx);
      next unless ($impact =~ m/HIGH|MODERATE/);
      next if ($effect eq 'sequence_feature');
      $genechange = $gene unless $genechange;
      $effectchange = $effect unless $effectchange;
      unless ($aachange) {
	  $aachange = $trx if ($aa);
      }
  }
  next W1 unless ($genechange);
  if ($aachange) {
      ($allele,$effect,$impact,$gene,$geneid,$feature,
       $featureid,$biotype,$rank,$codon,$aa,$pos_dna,$len_cdna,
       $cds_pos,$cds_len,$aapos,$aalen,$distance,$err) = split(/\|/,$aachange);
  }else {
      $gene = $genechange;
      $effect = $effectchange;
  }
  
  $rnaexpress = $fpkm{$gene} if ($fpkm{$gene});
  $incosmic = $cosmic{$gene} if ($cosmic{$gene});
  $innofone = $nofone{$gene} if ($nofone{$gene});
  $inrole = $roleincancer{$gene} if ($roleincancer{$gene});
  $incivic = $civic{$gene} if ($civic{$gene});
  #if ($hash{NF}) {
  #    $hash{SAR} = $hash{TR} - $hash{NF};
  #    $hash{SAF} = $hash{NF};
  #    $hash{SRR} = $hash{TCR}-$hash{SAR};
  #    $hash{SRF} = $hash{TCF}-$hash{SAF};
  #}
  print OUT join(",",join(":",$chrom,$pos),$id,$gene,$aa,$effect,$ref,$alt,
		 $somstatus,$hash{RnaSeqValidation},$rnaexpress,$innofone,$incosmic,$inrole,
		 $hash{AF},$hash{DP},$hash{NormalAF},$hash{NormalDP},$hash{RnaSeqAF},
		 $hash{RnaSeqDP},$strandbias,$incivic),"\n";
}

