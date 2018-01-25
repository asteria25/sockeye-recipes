#!/bin/bash
#
# Auto-tune a Neural Machine Translation model 
# Using Sockeye and CMA-ES algorithm

if [ $# -ne 2 ]; then
    echo "Usage: auto-tune.sh hyperparams.txt device(gpu/cpu)"
    exit
fi

###########################################
# (0) Hyperparameter settings
# source hyperparams.txt to get text files and all training hyperparameters
source $1

# options for cpu vs gpu training (may need to modify for different grids)
if [ $2 == "cpu" ]; then
    source activate sockeye_cpu_dev
    device="--use-cpu"
else
    source activate sockeye_gpu_dev
    module load cuda80/toolkit
    gpu_id=`$rootdir/scripts/get-gpu.sh`
    device="--device-id $gpu_id"
fi

###########################################
# (1) Hyperparameter auto-tuning
# exit when max generation reached
for ((n_generation=$n_generation;n_generation<$generation;n_generation++))
    do
        ###########################################
        # (1.1) set path and create folders
        if [ ! -d $checkpoint_path ]; then
          mkdir $checkpoint_path
        fi

        # path to current generation folder
        generation_path="${generation_dir}generation_$(printf "%02d" "$n_generation")/"
        
        # path to previous generation folder
        prev_generation_path="${prev_generation_dir}generation_$(printf "%02d" "`expr $n_generation - 1`")/"
        
        # path to current genes folder
        gene_path="${generation_path}genes/"

        # path to gene files
        gene="${gene_path}/%s.gene"

        mkdir $generation_path
        mkdir $gene_path

        ###########################################
        # (1.2) generate and record genes for current generation
        # save current generation information as a checkpoint
        $py_cmd evo_single.py \
        --checkpoint $checkpoint \
        --gene $gene \
        --params ${params} \
        --map-func $map_func \
        --scr ${prev_generation_path}genes.scr \
        --pop $population \
        --n-gen $n_generation 
        
        ###########################################
        # (1.3) train models described by model description file in current generation 
        for ((n_population=0;n_population<$population;n_population++))
          do
            # model folder
            model_path="${generation_path}model_$(printf "%02d" "$n_population")/"
            # path to evaluation score path
            eval_scr="${model_path}metrics"

            mkdir $model_path
            touch ${eval_scr}
            
            # # generate some fake score for testing
            # $py_cmd toy_nmt.py \
            # --trg $eval_scr \
            # --n-gen $n_generation \
            # --min-num-epochs $min_num_epochs

            # update the tuned hyperparameters
            source $(printf ${gene} $(printf "%02d" ${n_population}))
            
            # train the model
            $py_cmd -m sockeye.train -s ${train_bpe}.$src \
                        -t ${train_bpe}.$trg \
                        -vs ${valid_bpe}.$src \
                        -vt ${valid_bpe}.$trg \
                        --num-embed $num_embed \
                        --rnn-num-hidden $rnn_num_hidden \
                        --rnn-attention-type $attention_type \
                        --max-seq-len $max_seq_len \
                        --checkpoint-frequency $checkpoint_frequency \
                        --num-words $num_words \
                        --word-min-count $word_min_count \
                        --max-updates $max_updates \
                        --num-layers $num_layers \
                        --rnn-cell-type $rnn_cell_type \
                        --batch-size $batch_size \
                        --min-num-epochs $min_num_epochs \
                        --embed-dropout $embed_dropout \
                        --keep-last-params $keep_last_params \
                        --use-tensorboard \
                        $device \
                        -o $model_path

            # report result to gene.scr file
            $py_cmd reporter.py \
            --trg ${generation_path}genes.scr \
            --scr $eval_scr \
            --pop $population \
            --n-pop $n_population \
            --n-gen $n_generation

          done

    done
        # Finished