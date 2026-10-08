"""QLoRA fine-tune of Gemma 4 12B on data/{train,valid}.jsonl with Unsloth. Run on the CUDA box."""

import argparse

from unsloth import FastModel
from unsloth.chat_templates import get_chat_template, train_on_responses_only

from datasets import load_dataset
from trl import SFTConfig, SFTTrainer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="google/gemma-4-12B-it")
    ap.add_argument("--data", default="data")
    ap.add_argument("--out", default="outputs")
    ap.add_argument("--max-seq-length", type=int, default=2048)
    ap.add_argument("--epochs", type=float, default=1)
    ap.add_argument("--rank", type=int, default=16)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--gguf", action="store_true", help="also export a q4_k_m GGUF for llama.cpp / Ollama")
    args = ap.parse_args()

    model, tokenizer = FastModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
        full_finetuning=False,
    )
    model = FastModel.get_peft_model(
        model,
        finetune_vision_layers=False,
        finetune_language_layers=True,
        finetune_attention_modules=True,
        finetune_mlp_modules=True,
        r=args.rank,
        lora_alpha=args.rank,
        lora_dropout=0,
        bias="none",
        random_state=0,
    )
    tokenizer = get_chat_template(tokenizer, chat_template="gemma-4")

    def to_text(batch):
        texts = [tokenizer.apply_chat_template(m, tokenize=False) for m in batch["messages"]]
        return {"text": [t.removeprefix(tokenizer.bos_token) for t in texts]}

    ds = load_dataset("json", data_files={s: f"{args.data}/{s}.jsonl" for s in ("train", "valid")})
    ds = ds.map(to_text, batched=True, remove_columns=ds["train"].column_names)

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=ds["train"],
        eval_dataset=ds["valid"],
        args=SFTConfig(
            dataset_text_field="text",
            per_device_train_batch_size=2,
            gradient_accumulation_steps=8,
            num_train_epochs=args.epochs,
            learning_rate=args.lr,
            lr_scheduler_type="cosine",
            warmup_ratio=0.03,
            optim="adamw_8bit",
            logging_steps=10,
            eval_strategy="steps",
            eval_steps=200,
            save_steps=200,
            save_total_limit=3,
            output_dir=f"{args.out}/checkpoints",
            report_to="mlflow",
            seed=0,
        ),
    )
    trainer = train_on_responses_only(trainer, instruction_part="<|turn>user\n", response_part="<|turn>model\n")
    trainer.train()

    model.save_pretrained(f"{args.out}/lora")
    tokenizer.save_pretrained(f"{args.out}/lora")
    if args.gguf:
        model.save_pretrained_gguf(f"{args.out}/gguf", tokenizer, quantization_method="q4_k_m")


if __name__ == "__main__":
    main()
