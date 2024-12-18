#!/usr/bin/env nextflow

/* 
 * Predict protein function using PolyPhen
 */

params.pph_data = "/hps/nobackup/flicek/ensembl/variation/nuno/sift-polyphen2-nextflow-4667/input/polyphen2"

process get_pph2_version {
  container "ensemblorg/polyphen-2:2.2.3"
  output: stdout

  """
  cat /opt/pph2/VERSION | tr -d '\n'                                           
  """
}

process run_pph2_on_all_aminoacid_substitutions {
  /*
  Run PolyPhen-2 on a protein sequence with a substitions file

  Returns
  -------
  Returns 2 files:
      1) Output '*.txt'
      2) Errors '*.err'
  */

  tag "${peptide.md5}"
  container "ensemblorg/polyphen-2:2.2.3"
  containerOptions "--bind ${params.pph_data}:/opt/pph2/data"
  label 'retry_before_ignoring'

  input:
    val peptide

  output:
    tuple val(peptide), path ('*_scores.txt'), optional: true

  afterScript 'rm -rf *.fa *.subs tmp/'

  shell:
  '''
  subs=!{peptide.id}.subs
  create_aa_substitutions.sh polyphen2 !{peptide.id} \
                             "!{peptide.seqString}" > ${subs}

  fasta=!{peptide.id}.fa
  cat > ${fasta} <<EOL
!{peptide.text}EOL

  mkdir -p tmp/lock
  out=!{peptide.id}_scores.txt
  /opt/pph2/bin/run_pph.pl -A -d tmp -s ${fasta} ${subs} > $out

  # Remove output if only contains header
  if [ "$( wc -l <$out )" -eq 1 ]; then rm $out; fi
  '''
}

process run_weka {
  /*
  Run Weka

  Returns
  -------
  Returns 2 files:
      1) Output '*.txt'
      2) Error '*.err'
  */

  tag "${peptide.md5} ${model}"
  container "ensemblorg/polyphen-2:2.2.3"
  label 'retry_before_ignoring'

  input:
    each model
    tuple val(peptide), path(pph2_out)

  output:
    tuple val(peptide), path('*.txt'), val("${model}")

  """
  run_weka.pl -l /opt/pph2/models/${model} ${pph2_out} \
              > ${pph2_out.baseName}_${model}.txt
  """
}

process store_pph2_scores {
  tag "${peptide.md5} ${model}"
  container "ensemblorg/ensembl-vep:latest"
  label 'retry_before_ignoring'

  cache false

  input:
    val ready
    val species
    tuple val(peptide), path(weka_output), val(model)

  output:
    stdout

  """
  store_polyphen_scores.pl ${species} ${params.offline} ${params.sqlite_db} \
                           ${params.port} ${params.host} ${params.user} ${params.pass} ${params.database} \
                           ${peptide.seqString} ${weka_output} ${model}
  """
}

// module imports                                                               
include { delete_prediction_data; update_meta } from './database_utils.nf'        
include { filter_existing_translations        } from './translations.nf'

workflow run_pph2_pipeline {
  take: 
    translated
    sqlite_db_prep
  main:
  if ( params.pph_run_type == "UPDATE" && !params.offline ) {
    translated = filter_existing_translations( "polyphen_%", translated )
    wait = "ready"
  } else if ( params.pph_run_type == "FULL" && !params.offline ) {
    delete_prediction_data("polyphen_%")
    wait = delete_prediction_data.out
    get_pph2_version()
    update_meta("polyphen_version", get_pph2_version.out)
  } else {
    wait = "ready"
  }
  // Run PolyPhen-2 and Weka
  run_pph2_on_all_aminoacid_substitutions(translated)

  weka_model = Channel.of("HumDiv.UniRef100.NBd.f11.model",
                          "HumVar.UniRef100.NBd.f11.model")
  run_weka(weka_model, run_pph2_on_all_aminoacid_substitutions.out)
  store_pph2_scores(wait, // wait for data deletion
                    params.species, run_weka.out)
  emit:
    store_sift_scores.out
}
