"""Adds YAMNet's 1024-number embedding as a second output of android/app/src/main/assets/yamnet.tflite.

Song radio compares songs by this embedding (the layer that YAMNet's 521 class scores are
computed from). The stock model only outputs the scores; the embedding layer is already in it,
so this only lists that tensor as an output too. Weights and the scores stay exactly the same.

Run once from the repository root (it does nothing when the output is already there):

    pip install ai-edge-litert numpy
    python3 tool/yamnet_add_embedding_output.py

It checks the result: the scores must equal the stock model's for the same input.
"""

import sys
from pathlib import Path

import flatbuffers
import numpy as np
from ai_edge_litert.interpreter import Interpreter
from ai_edge_litert.schema_py_generated import Model, ModelT

MODEL = Path("android/app/src/main/assets/yamnet.tflite")
EMBEDDING = "layer28/reduce_mean"


def run(path: Path) -> list[np.ndarray]:
    it = Interpreter(model_path=str(path))
    it.allocate_tensors()
    x = (np.random.default_rng(0).standard_normal(15600) * 0.1).astype(np.float32)
    it.set_tensor(it.get_input_details()[0]["index"], x)
    it.invoke()
    return [it.get_tensor(o["index"]).copy() for o in it.get_output_details()]


def main() -> int:
    stock = MODEL.read_bytes()
    model = ModelT.InitFromObj(Model.GetRootAsModel(stock, 0))
    graph = model.subgraphs[0]
    emb = next(i for i, t in enumerate(graph.tensors) if t.name.decode().endswith(EMBEDDING))
    if emb in list(graph.outputs):
        print("the embedding is already an output: nothing to do")
        return 0

    graph.outputs = list(graph.outputs) + [emb]
    builder = flatbuffers.Builder(0)
    builder.Finish(model.Pack(builder), file_identifier=b"TFL3")

    before = run(MODEL)
    patched = MODEL.with_suffix(".patched")
    patched.write_bytes(builder.Output())
    after = run(patched)
    if len(after) != 2 or not np.array_equal(before[0], after[0]) or after[1].size != 1024:
        patched.unlink()
        print("the patched model doesn't give the same scores plus a 1024 embedding", file=sys.stderr)
        return 1
    patched.replace(MODEL)
    print(f"done: {MODEL} now has 2 outputs (scores, embedding)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
