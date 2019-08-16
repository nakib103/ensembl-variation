# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More;
use Test::Deep;
use Test::Exception;
use FindBin qw($Bin);
use File::Path qw(remove_tree);
use Bio::EnsEMBL::Test::TestUtils;
use Bio::EnsEMBL::Variation::Utils::AncestralAllelesUtils;
use Bio::EnsEMBL::Variation::Utils::FastaSequence qw(setup_fasta);

my $fasta = "$Bin\/testdata/ancestral_fasta.fa";

my $db = setup_fasta(-FASTA => $fasta);
ok($db, "basic");
ok($db->isa('Bio::DB::HTS::Faidx') || $db->isa('Bio::DB::Fasta'), "isa");

my $ancestral_alleles_utils = Bio::EnsEMBL::Variation::Utils::AncestralAllelesUtils->new(-fasta_db => $db);

is($ancestral_alleles_utils->assign(4, 5, 4), undef, "Don't assign for ancestral allele for insertion");

is($ancestral_alleles_utils->assign(4, 5, 54), 'AAATAGATAAATAAATAAATAACCAACAGGCCGGGAGCAGTGGCTCACGC', "Ancestral allele smaller than or equal to 50bp");

is($ancestral_alleles_utils->assign(4, 5, 55), undef, "Don't assign ancestral allele if input region is larger than 50bp");

is($ancestral_alleles_utils->assign(4, 329, 329), 'A', "Ancestral allele at position 4:329-329");

is($ancestral_alleles_utils->assign(4, 330, 330), undef, "Don't assign ancestral allele if ancestral genome contains non ACGT chars in input region");

my $sequence_ids = $ancestral_alleles_utils->sequence_id_mappings;
cmp_deeply($sequence_ids, { '4' => 'ANCESTOR_for_chromosome:GRCh38:4:1:190214555:1' }, "Get sequence_id_mappings");

$ancestral_alleles_utils = Bio::EnsEMBL::Variation::Utils::AncestralAllelesUtils->new(-fasta_db => 'fasta_db');
throws_ok(sub{$ancestral_alleles_utils->assign(4, 5, 5)},qr/ERROR: Couldn't get sequence ids from/, 'Throws if fasta db is neither Bio::DB::HTS::Faidx nor Bio::DB::Fasta');

unlink("$fasta\.index");
unlink("$fasta\.fai");

$fasta = "$Bin\/testdata/ancestral_fasta_unexpected_sequence_ids.fa";
$db = setup_fasta(-FASTA => $fasta);
ok($db, "basic");
ok($db->isa('Bio::DB::HTS::Faidx') || $db->isa('Bio::DB::Fasta'), "isa");

$ancestral_alleles_utils = Bio::EnsEMBL::Variation::Utils::AncestralAllelesUtils->new(-fasta_db => $db);
throws_ok(sub{$ancestral_alleles_utils->assign(4, 5, 5)},qr/ERROR: sequence ids have changed and don't follow the expected pattern of colon separated values/, 'Throws if sequence ids in ancestral fasta file have changed.');

unlink("$fasta\.index");
unlink("$fasta\.fai");

done_testing();
