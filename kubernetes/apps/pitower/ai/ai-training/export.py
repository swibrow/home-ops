"""Merge a LoRA adapter into its base model and export a GGUF for llama.cpp."""

import argparse

from unsloth import FastModel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True, help="directory written by train.py as <out>/lora")
    ap.add_argument("--out", required=True)
    ap.add_argument("--quant", default="q4_k_m")
    ap.add_argument("--max-seq-length", type=int, default=2048)
    args = ap.parse_args()

    model, tokenizer = FastModel.from_pretrained(
        model_name=args.adapter,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
    )
    model.save_pretrained_gguf(args.out, tokenizer, quantization_method=args.quant)


if __name__ == "__main__":
    main()
