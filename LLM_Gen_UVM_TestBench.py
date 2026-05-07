#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║                        UVM TestBench Generator                               ║
║                                                                              ║
║  Automated UVM testbench generation from RTL designs using LLM APIs.         ║
║  Routes all requests through the Portkey AI Gateway (NYU cloud infra)        ║
║  or direct API Calls                                                         ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""

import os
import sys
import argparse
import logging
import time
import re
import threading
from datetime import datetime
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

# ─────────────────────────────────────────────────────────────────────────────
# Global State 
# ─────────────────────────────────────────────────────────────────────────────
api_key = None
client = None
model = None
max_tokens = 16384

PORTKEY_BASE_URL = "https://ai-gateway.apps.cloud.rt.nyu.edu/v1"

# Set by --backend CLI flag.  Possible values:
#   "portkey"  – original NYU Portkey AI Gateway path (default, unchanged)
#   "direct"   – call OpenAI / Anthropic / Google APIs directly with the
#                user's own API key obtained from the provider's website.
backend = "portkey"

# Direct-provider routing.  When backend == "direct" the script wraps the
# chosen provider in one of the AbstractLLM subclasses below (ChatGPT /
# Claude / Gemini).  Selection convention:
#   • `model_choice` global 
#     "Select Model" cell) chooses the specific model VERSION
#     (e.g. "gpt-4o", "claude-sonnet-4-5", "gemini-2.5-flash")
#   • `os.environ["MODEL"]` chooses the PROVIDER WRAPPER CLASS
#     (one of "ChatGPT" / "Claude" / "Gemini")
#   • Each wrapper class reads its API key from var names: OPENAI_API_KEY / CLAUDE_API_KEY / GEMINI_API_KEY
# All three can be overridden at the CLI with --model-choice, --provider,
# and the standard env vars; see the argparse block at the bottom.
direct_provider = None   # "ChatGPT" | "Claude" | "Gemini" 
direct_llm = None        # The AbstractLLM instance for the chosen provider

# style use, or override with --model-choice on the CLI.
model_choice = "gpt-4o"
# model_choice = "gpt-5.2"
# model_choice = "claude-sonnet-4-5"
# model_choice = "gemini-2.5-flash"

tqdm_lock = threading.Lock()

# ─────────────────────────────────────────────────────────────────────────────
# Logging Configuration
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("uvm_gen.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# System Prompt
# ─────────────────────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """\
You are an expert verification engineer specialising in UVM (Universal \
Verification Methodology) and SystemVerilog. Given a design file that \
contains RTL code, a SystemVerilog interface, and SystemVerilog Assertions \
(SVA), you analyse the design intent, identify all protocols and functional \
requirements, then produce a complete, compilable UVM testbench. You use the \
interface already defined in the file — you do NOT generate a new one. You \
ensure the testbench exercises scenarios that cover the SVA properties. \
Your output must be production-quality code with meaningful comments and \
must follow standard UVM coding conventions."""

# ─── NEW: System prompt used when input is a .txt specification ──────────────
# Treats the spec as the contract; the LLM must invent the interface and SVA
# itself (since no RTL/interface/SVA is provided), but everything else stays
# the same.
SYSTEM_PROMPT_SPEC = """\
You are an expert verification engineer specialising in UVM (Universal \
Verification Methodology) and SystemVerilog. Given a natural-language \
specification document describing a hardware design, you treat the \
specification as the authoritative contract for the DUT's behaviour. \
You do NOT generate the RTL design itself — only the UVM testbench. \
You infer the DUT's port list, protocols, clocking, and reset behaviour \
from the specification, define a SystemVerilog interface that matches \
the inferred ports, and write SVA properties that encode the spec's \
functional requirements so the testbench can verify them. Your output \
must be production-quality code with meaningful comments and must \
follow standard UVM coding conventions."""

# ─────────────────────────────────────────────────────────────────────────────
# UVM Component Definitions
# ─────────────────────────────────────────────────────────────────────────────
UVM_COMPONENTS = {
    "tb_top": {
        "label": "UVM Top (tb_top)",
        "desc": (
            "SystemVerilog module that instantiates the DUT, creates "
            "virtual interfaces, generates clock and reset, and calls "
            "run_test()."
        ),
    },
    "test": {
        "label": "Test (uvm_test)",
        "desc": (
            "Top-level UVM test class that configures the environment, "
            "sets configuration objects, and initiates the default sequence."
        ),
    },
    "env": {
        "label": "Environment (uvm_env)",
        "desc": (
            "Container class that instantiates agents, scoreboards, "
            "functional-coverage collectors, and connects analysis ports."
        ),
    },
    "agent": {
        "label": "Agent (uvm_agent)",
        "desc": (
            "Bundles a driver, sequencer, and monitor for each DUT "
            "interface. Supports both ACTIVE and PASSIVE modes."
        ),
    },
    "sequencer": {
        "label": "Sequencer (uvm_sequencer)",
        "desc": (
            "Parameterised sequencer that manages transaction flow "
            "from sequences to the driver."
        ),
    },
    "driver": {
        "label": "Driver (uvm_driver)",
        "desc": (
            "Converts sequence-item transactions into pin-level DUT "
            "stimulus via the virtual interface."
        ),
    },
    "monitor": {
        "label": "Monitor (uvm_monitor)",
        "desc": (
            "Samples DUT interface signals and broadcasts captured "
            "transactions through an analysis port."
        ),
    },
    "scoreboard": {
        "label": "Scoreboard (uvm_scoreboard)",
        "desc": (
            "Receives transactions from monitors, computes expected "
            "results with a reference model, and checks correctness."
        ),
    },
    "sequence_item": {
        "label": "Sequence Item (uvm_sequence_item)",
        "desc": (
            "Data object representing a single transaction with "
            "randomisable fields and constraints."
        ),
    },
    "sequence": {
        "label": "Sequence (uvm_sequence)",
        "desc": (
            "Defines stimulus scenarios by generating and sending "
            "sequence items to the sequencer."
        ),
    },
    "coverage": {
        "label": "Functional Coverage (uvm_subscriber)",
        "desc": (
            "Collects functional-coverage data using covergroups "
            "and coverpoints to track verification completeness."
        ),
    },
}

# ─────────────────────────────────────────────────────────────────────────────
# Backend Setup – Portkey AI Gateway
# ─────────────────────────────────────────────────────────────────────────────
def setup():
    """Initialise the Portkey AI Gateway client."""
    global api_key, client

    logger.info("Setting up Portkey AI Gateway client...")

    from portkey_ai import Portkey

    api_key = os.getenv("PORTKEY_API_KEY")
    if not api_key:
        raise ValueError(
            "PORTKEY_API_KEY environment variable not set. "
            "Set it with:  export PORTKEY_API_KEY='your-key'"
        )

    client = Portkey(
        base_url=PORTKEY_BASE_URL,
        api_key=api_key,
    )

    logger.info(f"✅ Portkey client initialised (gateway: {PORTKEY_BASE_URL})")


# ═════════════════════════════════════════════════════════════════════════════
# Direct-Provider Backend
# ═════════════════════════════════════════════════════════════════════════════
#
#   • OpenAI    →  OPENAI_API_KEY    (https://platform.openai.com/api-keys)
#   • Anthropic →  CLAUDE_API_KEY    (https://console.anthropic.com/)
#                  ↑ NOT Anthropic's own ANTHROPIC_API_KEY default 
#   • Google    →  GEMINI_API_KEY    (https://aistudio.google.com/apikey)
#                  ↑ NOT Google's own GOOGLE_API_KEY default — same reason.
#
# PROVIDER SELECTION (priority order):
#   1. --provider {ChatGPT,Claude,Gemini}     CLI flag (highest precedence)
#   2. os.environ["MODEL"]                    
#   3. Auto-detect from model_choice prefix   (gpt-/o-series → ChatGPT,
#                                              claude-       → Claude,
#                                              gemini-       → Gemini)
# ═════════════════════════════════════════════════════════════════════════════


from abc import ABC, abstractmethod


# ─── AbstractLLM ───────
class AbstractLLM(ABC):
    """Abstract Large Language Model."""

    def __init__(self):
        pass

    @abstractmethod
    def generate(self, prompt: str, system_prompt: str) -> str:
        """Generate a response based on the given prompt + system prompt.

        Returns the response text as a string.

        NOTE: UVM testbench script uses a
        single-shot prompt + system prompt 
        """
        pass


# ─── ChatGPT wrapper  ──────────────────────────
class ChatGPT(AbstractLLM):
    """ChatGPT Large Language Model."""

    def __init__(self, model_id=None):
        super().__init__()
        import openai
        if "OPENAI_API_KEY" not in os.environ or not os.environ["OPENAI_API_KEY"]:
            raise ValueError(
                "OPENAI_API_KEY environment variable not set. "
                "Get a key at https://platform.openai.com/api-keys and set: "
                "os.environ['OPENAI_API_KEY'] = 'sk-...'  (or export it in your shell)"
            )
        openai.api_key = os.environ["OPENAI_API_KEY"]
        self.client = openai.OpenAI()
        self.model_id = model_id if model_id else model_choice

    def generate(self, prompt: str, system_prompt: str) -> str:
        completion = self.client.chat.completions.create(
            model=self.model_id,
            max_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user",   "content": prompt},
            ],
        )
        choice = completion.choices[0]
        text = choice.message.content
        finish_reason = getattr(choice, "finish_reason", None)
        _direct_diagnostics(text, finish_reason, "ChatGPT")
        return text


# ─── Claude wrapper ────────
class Claude(AbstractLLM):
    def __init__(self, model_id=None):
        super().__init__()
        import anthropic
        if "CLAUDE_API_KEY" not in os.environ or not os.environ["CLAUDE_API_KEY"]:
            raise ValueError(
                "CLAUDE_API_KEY environment variable not set. "
                "Get a key at https://console.anthropic.com/ and set: "
                "os.environ['CLAUDE_API_KEY'] = 'sk-ant-...'  (or export it in your shell)"
            )
        self.client = anthropic.Anthropic(api_key=os.environ["CLAUDE_API_KEY"])
        self.model_id = model_id if model_id else model_choice

    def generate(self, prompt: str, system_prompt: str) -> str:
        message = self.client.messages.create(
            model=self.model_id,
            max_tokens=max_tokens,
            system=system_prompt,
            messages=[{"role": "user", "content": prompt}],
        )
        # Anthropic returns a list of content blocks; concat all text blocks.
        text = "".join(
            block.text for block in message.content
            if getattr(block, "type", None) == "text"
        ) or None
        finish_reason = getattr(message, "stop_reason", None)
        _direct_diagnostics(text, finish_reason, "Claude")
        return text


# ─── Gemini wrapper ────────────────────────────
class Gemini(AbstractLLM):
    def __init__(self, model_id=None):
        super().__init__()
        from google import genai
        if "GEMINI_API_KEY" not in os.environ or not os.environ["GEMINI_API_KEY"]:
            raise ValueError(
                "GEMINI_API_KEY environment variable not set. "
                "Get a key at https://aistudio.google.com/apikey and set: "
                "os.environ['GEMINI_API_KEY'] = '...'  (or export it in your shell)"
            )
        self.gemini_client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
        self.model_id = model_id if model_id else model_choice

    def generate(self, prompt: str, system_prompt: str) -> str:
        from google.genai import types as genai_types
        result = self.gemini_client.models.generate_content(
            model=self.model_id,
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                system_instruction=system_prompt,
                max_output_tokens=max_tokens,
            ),
        )
        text = result.text
        finish_reason = None
        if result.candidates:
            finish_reason = getattr(result.candidates[0], "finish_reason", None)
        _direct_diagnostics(text, finish_reason, "Gemini")
        return text



_PROVIDER_CLASSES = {
    "ChatGPT": ChatGPT,
    "Claude":  Claude,
    "Gemini":  Gemini,
}


def generate_uvm_tb(prompt: str, system_prompt: str, model_type: str = None,
                    model_id: str = "") -> str:
    """.

    Routes to the correct wrapper class based on `model_type` (one of
    "ChatGPT", "Claude", "Gemini").  If `model_type` is omitted, falls
    back to os.environ["MODEL"].
    """
    global direct_llm

    if model_type is None:
        model_type = os.environ.get("MODEL")
        if not model_type:
            raise ValueError(
                "No provider specified.  Pass --provider, set "
                "os.environ['MODEL'], or omit to auto-detect from model_choice."
            )

    if model_type not in _PROVIDER_CLASSES:
        raise ValueError(
            f"Invalid model type '{model_type}'.  "
            f"Choose one of: {list(_PROVIDER_CLASSES)}"
        )

    # Cache the instance — re-instantiating per call would re-read the env
    # var and re-construct the client every time.
    if direct_llm is None or direct_llm.__class__.__name__ != model_type:
        cls = _PROVIDER_CLASSES[model_type]
        direct_llm = cls(model_id=model_id) if model_id else cls()
        logger.info(f"✅ Direct backend instantiated: {model_type} "
                    f"(model_id={direct_llm.model_id})")

    return direct_llm.generate(prompt, system_prompt)


# ─── Helpers used by the wrappers above ──────────────────────────────────────
def _autodetect_provider(model_name: str) -> str:
    """Infer ChatGPT/Claude/Gemini from a bare model name prefix."""
    m = (model_name or "").lower().strip()
    if m.startswith(("gpt-", "o1", "o3", "o4-")):
        return "ChatGPT"
    if m.startswith("claude-"):
        return "Claude"
    if m.startswith("gemini-"):
        return "Gemini"
    raise ValueError(
        f"Cannot auto-detect provider for model_choice='{model_name}'.  "
        f"Set --provider explicitly, or set os.environ['MODEL'] to one of "
        f"{list(_PROVIDER_CLASSES)}."
    )


def _direct_diagnostics(text, finish_reason, provider_label: str):
    """Same None-content + truncation diagnostics the Portkey path uses.
    Raises on None content; warns on truncation; logs success."""
    if text is None:
        raise ValueError(
            f"LLM returned None content (provider={provider_label}, "
            f"finish_reason={finish_reason}).  This usually means a safety "
            f"filter triggered or the model produced no output."
        )
    truncation_reasons = ("length", "max_tokens", "MAX_TOKENS",
                          "max_output_tokens")
    if str(finish_reason) in truncation_reasons:
        logger.warning(
            f"⚠️  Response TRUNCATED at {len(text)} chars "
            f"(provider={provider_label}, finish_reason={finish_reason}).  "
            f"Increase --max-tokens or split the prompt."
        )
    logger.info(
        f"API response received ({len(text)} chars, "
        f"finish_reason={finish_reason}, provider={provider_label})"
    )


def setup_direct(cli_provider: str = None):
    """Initialise the direct-provider wrapper .

    Resolution order:
      1. cli_provider arg          (from --provider CLI flag)
      2. os.environ["MODEL"]      
      3. Auto-detect from model_choice prefix
    """
    global direct_provider, direct_llm

    if cli_provider:
        if cli_provider not in _PROVIDER_CLASSES:
            raise ValueError(
                f"Unknown --provider '{cli_provider}'.  "
                f"Choose one of: {list(_PROVIDER_CLASSES)}"
            )
        direct_provider = cli_provider
    elif os.environ.get("MODEL") in _PROVIDER_CLASSES:
        direct_provider = os.environ["MODEL"]
    else:
        direct_provider = _autodetect_provider(model_choice)

    logger.info(f"Setting up DIRECT backend → "
                f"provider={direct_provider}, model_choice={model_choice}")

    # Eagerly instantiate so missing API keys fail fast at startup, not
    # on the first generation call inside a worker thread.
    cls = _PROVIDER_CLASSES[direct_provider]
    direct_llm = cls()
    logger.info(f"✅ {direct_provider} client initialised "
                f"(model_id={direct_llm.model_id})")


def _make_api_call_direct(prompt: str, system_prompt: str) -> str:
    """Direct-provider counterpart to _make_api_call().

    Same return contract as the Portkey path.  Just delegates to the
    cached AbstractLLM instance via generate_uvm_tb().
    """
    return generate_uvm_tb(prompt, system_prompt, model_type=direct_provider)


# ─────────────────────────────────────────────────────────────────────────────
# Design Loading
# ─────────────────────────────────────────────────────────────────────────────
def load_designs(directory: str):
    """Load all .v / .sv files from *directory*."""
    designs = []
    for fname in sorted(os.listdir(directory)):
        if fname.endswith((".v", ".sv")):
            with open(os.path.join(directory, fname), "r") as fh:
                designs.append((fname, fh.read()))
    if not designs:
        logger.warning(f"No .v/.sv files found in {directory}")
    return designs


def load_single_design(file_path: str):
    """Load one RTL file."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Design file not found: {file_path}")
    with open(file_path, "r") as fh:
        return [(os.path.basename(file_path), fh.read())]


# ─── NEW: Spec-file loaders (additive — original loaders are untouched) ──────
def load_single_spec(file_path: str):
    """Load one .txt specification file."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Spec file not found: {file_path}")
    with open(file_path, "r") as fh:
        return [(os.path.basename(file_path), fh.read())]


def load_inputs(file_path: str):
    """
    Auto-dispatch to the correct loader based on file extension.

    .v / .sv  → load_single_design  (original RTL path)
    .txt      → load_single_spec    (new specification path)
    """
    ext = os.path.splitext(file_path)[1].lower()
    if ext in (".v", ".sv"):
        return load_single_design(file_path), "rtl"
    if ext == ".txt":
        return load_single_spec(file_path), "spec"
    raise ValueError(
        f"Unsupported input file extension '{ext}'. "
        f"Expected .v, .sv, or .txt."
    )


def load_inputs_dir(directory: str):
    """
    Directory loader that accepts both RTL and spec files.

    Returns a list of (filename, contents, kind) tuples where kind is
    "rtl" for .v/.sv files and "spec" for .txt files.
    """
    items = []
    for fname in sorted(os.listdir(directory)):
        full = os.path.join(directory, fname)
        if fname.endswith((".v", ".sv")):
            with open(full, "r") as fh:
                items.append((fname, fh.read(), "rtl"))
        elif fname.endswith(".txt"):
            with open(full, "r") as fh:
                items.append((fname, fh.read(), "spec"))
    if not items:
        logger.warning(f"No .v/.sv/.txt files found in {directory}")
    return items


# ─────────────────────────────────────────────────────────────────────────────
# Prompt Construction
# ─────────────────────────────────────────────────────────────────────────────
def _component_spec_block() -> str:
    """Build the section of the prompt that lists every required component."""
    lines = []
    for key, comp in UVM_COMPONENTS.items():
        lines.append(f"### {comp['label']}\n{comp['desc']}")
    return "\n\n".join(lines)


def construct_prompt(design_code: str, design_name: str) -> str:
    """Return the full LLM prompt for UVM testbench generation."""
    return f"""\
Analyse the following design file and generate a **complete, compilable UVM \
testbench** that thoroughly verifies it.

The file contains three things:
  1. **RTL design** – the module(s) to be verified (the DUT).
  2. **SystemVerilog interface** – already written; use it as-is.
  3. **SystemVerilog Assertions (SVA)** – properties the design must satisfy.

=== DESIGN FILE ({design_name}) ===
```
{design_code}
```
=== END DESIGN FILE ===

─────────────────────────────────
REQUIRED UVM COMPONENTS
─────────────────────────────────
Generate ALL of the following components. Each component must be enclosed in
its own clearly labelled code block.

**IMPORTANT: Do NOT generate a SystemVerilog interface.** The interface is
already defined in the design file above. All generated components (driver,
monitor, tb_top, etc.) must use that existing interface exactly as-is.

{_component_spec_block()}

─────────────────────────────────
GENERAL REQUIREMENTS
─────────────────────────────────
1. Analyse the design file thoroughly: identify the RTL module(s), the
   provided interface (with its clocking blocks), and every SVA property
   before writing any code.
2. Use the **provided SystemVerilog interface** as-is. Do NOT create a new
   one. The driver, monitor, and tb_top must reference the interface and
   its clocking blocks exactly as defined in the design file.
3. The testbench must exercise scenarios that trigger and cover the **SVA
   properties** in the design file. The scoreboard or checker should
   complement (not duplicate) the SVA checks.
4. The **sequence item** must have randomisable fields with meaningful
   constraints that exercise corner cases (boundary values, zero, max, overflow).
5. The **driver** must faithfully translate transactions to pin wiggles using
   the clocking block defined in the provided interface.
6. The **monitor** must sample independently of the driver and broadcast
   transactions via an analysis port, using the provided interface's
   monitor clocking block.
7. The **scoreboard** must contain a reference model that independently
   computes the expected output and compares it against actual DUT output.
8. The **functional coverage** component must include covergroups with
   coverpoints for all key signals and cross-coverage where appropriate.
9. The **sequence** must include at least:
   - A reset/initialisation sequence
   - A directed corner-case sequence
   - A constrained-random sequence
10. The **test** must configure the environment, set the virtual interface via
    uvm_config_db, and start the default sequence.
11. The **tb_top** must generate clock and reset, instantiate the DUT, bind
    the provided interface, store the virtual interface in uvm_config_db,
    and call `run_test()`.
12. All code must be fully compilable with standard UVM-1.2+ simulators.
13. Add clear comments explaining design-intent decisions.
14. The very first two lines of the testbench output (before any of the
    other components) **must** be:
    ```
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    ```
    These two lines must appear at the top, before the SEQUENCE_ITEM and
    all subsequent component code blocks.
15. Ensure that **all written text, explanations, labels, or decorative
    symbols** that are not valid SystemVerilog code are commented out
    using `//`. The output must be directly compilable — no bare prose
    or non-code text outside of comments.

─────────────────────────────────
OUTPUT FORMAT (strictly follow)
─────────────────────────────────
Return your response using **exactly** these section headers. Each section
must appear **exactly once**. Do NOT repeat or rephrase any section.

ANALYSIS:
<Brief analysis of the design: RTL purpose, I/O ports, protocols, clock/reset,
 summary of the provided interface and SVA properties found in the file>

SEQUENCE_ITEM:
```systemverilog
<sequence item code>
```

SEQUENCE:
```systemverilog
<sequence code>
```

SEQUENCER:
```systemverilog
<sequencer code>
```

DRIVER:
```systemverilog
<driver code>
```

MONITOR:
```systemverilog
<monitor code>
```

SCOREBOARD:
```systemverilog
<scoreboard code>
```

COVERAGE:
```systemverilog
<functional coverage subscriber code>
```

AGENT:
```systemverilog
<agent code>
```

ENV:
```systemverilog
<environment code>
```

TEST:
```systemverilog
<test code>
```

TB_TOP:
```systemverilog
<tb_top module code>
```

COMPILE_ORDER:
<List the files in the order they should be compiled>

CRITICAL INSTRUCTION: Do NOT generate an INTERFACE section — the interface \
is already provided in the design file. Provide only one instance of each \
section above. Do not repeat or rephrase your response under any circumstances.
"""


# ─── NEW: Spec-driven prompt (additive, original construct_prompt unchanged) ─
def construct_prompt_spec(spec_text: str, spec_name: str) -> str:
    """
    Return the LLM prompt for the case where input is a .txt specification.

    The spec is treated as the contract.  The LLM must:
      • infer the DUT's port list and protocols from the spec
      • DEFINE its own SystemVerilog interface (since none is provided)
      • DEFINE its own SVA properties that encode the spec's requirements
      • produce all the usual UVM components against that interface

    NOTE: The DUT itself is NOT generated — the user is expected to write
    the RTL separately, or use the testbench against an existing DUT whose
    behaviour matches the spec.
    """
    return f"""\
Read the following natural-language specification document and generate a \
**complete, compilable UVM testbench** that verifies a DUT conforming to \
the spec.

The input is a plain-text specification — there is **no RTL, no interface, \
and no SVA provided**.  You must:
  1. Infer the DUT's port list, widths, protocols, clocking, and reset
     behaviour from the specification.
  2. **Define a SystemVerilog interface** that matches the inferred ports,
     including appropriate clocking blocks for driver and monitor.
  3. **Write SystemVerilog Assertions (SVA)** inside the interface (or in
     a bound module) that encode the functional requirements stated in
     the spec.
  4. Generate every other UVM component as usual.

You are NOT generating the DUT itself — only the verification environment.
Assume the user will supply (or has already written) an RTL module whose
behaviour matches this specification and whose port list matches the
interface you define.

=== SPECIFICATION FILE ({spec_name}) ===
```
{spec_text}
```
=== END SPECIFICATION FILE ===

─────────────────────────────────
REQUIRED UVM COMPONENTS
─────────────────────────────────
Generate ALL of the following components. Each component must be enclosed in
its own clearly labelled code block.

**IMPORTANT: Because no interface was provided, you MUST generate one in
this case.**  Place the interface (with clocking blocks and embedded SVA)
in the INTERFACE section below.

{_component_spec_block()}

─────────────────────────────────
GENERAL REQUIREMENTS
─────────────────────────────────
1. Re-read the specification carefully and enumerate every functional
   requirement before writing any code.  Treat the spec as the
   authoritative contract — if the spec is silent on something, choose
   sensible defaults and document them in comments.
2. The **interface you generate** must include a clocking block for the
   driver, a clocking block for the monitor, and SVA properties that
   encode the spec's requirements.
3. The testbench must exercise scenarios that trigger and cover every
   SVA property you wrote.  The scoreboard or checker should complement
   (not duplicate) the SVA checks.
4. The **sequence item** must have randomisable fields with meaningful
   constraints that exercise corner cases (boundary values, zero, max,
   overflow) implied by the spec.
5. The **driver** must faithfully translate transactions to pin wiggles
   using the clocking block defined in the interface you generated.
6. The **monitor** must sample independently of the driver and broadcast
   transactions via an analysis port.
7. The **scoreboard** must contain a reference model — based directly on
   the spec — that independently computes the expected output and
   compares it against actual DUT output.
8. The **functional coverage** component must include covergroups with
   coverpoints for every key behaviour described in the spec, plus
   cross-coverage where appropriate.
9. The **sequence** must include at least:
   - A reset/initialisation sequence
   - A directed corner-case sequence
   - A constrained-random sequence
10. The **test** must configure the environment, set the virtual interface
    via uvm_config_db, and start the default sequence.
11. The **tb_top** must generate clock and reset, instantiate the DUT
    (assume a module name derived from the spec, and document the
    assumed port list in comments), bind the generated interface, store
    the virtual interface in uvm_config_db, and call `run_test()`.
12. All code must be fully compilable with standard UVM-1.2+ simulators.
13. Add clear comments explaining every design-intent decision and every
    assumption inferred from (or filling gaps in) the specification.
14. The very first two lines of the testbench output **must** be:
    ```
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    ```
15. Ensure that **all written text, explanations, labels, or decorative
    symbols** that are not valid SystemVerilog code are commented out
    using `//`.

─────────────────────────────────
OUTPUT FORMAT (strictly follow)
─────────────────────────────────
Return your response using **exactly** these section headers. Each section
must appear **exactly once**. Do NOT repeat or rephrase any section.

ANALYSIS:
<Brief analysis of the spec: DUT purpose, inferred I/O ports, protocols,
 clock/reset, the SVA properties you intend to write, and any assumptions
 you are making to fill spec gaps.>

INTERFACE:
```systemverilog
<SystemVerilog interface with clocking blocks and embedded SVA properties>
```

SEQUENCE_ITEM:
```systemverilog
<sequence item code>
```

SEQUENCE:
```systemverilog
<sequence code>
```

SEQUENCER:
```systemverilog
<sequencer code>
```

DRIVER:
```systemverilog
<driver code>
```

MONITOR:
```systemverilog
<monitor code>
```

SCOREBOARD:
```systemverilog
<scoreboard code>
```

COVERAGE:
```systemverilog
<functional coverage subscriber code>
```

AGENT:
```systemverilog
<agent code>
```

ENV:
```systemverilog
<environment code>
```

TEST:
```systemverilog
<test code>
```

TB_TOP:
```systemverilog
<tb_top module code>
```

COMPILE_ORDER:
<List the files in the order they should be compiled>

CRITICAL INSTRUCTION: Provide only one instance of each section above. \
Do not repeat or rephrase your response under any circumstances.
"""


# ─────────────────────────────────────────────────────────────────────────────
# LLM Inference with Retry 
# ─────────────────────────────────────────────────────────────────────────────
def model_inference(
    prompt: str,
    max_retries: int = 3,
    retry_delay: int = 1,
    system_prompt: str = SYSTEM_PROMPT,
) -> str:
    """Call the LLM with retry + exponential backoff.

    Routes to either the Portkey or Direct backend based on the global
    `backend` setting.  Accepts an explicit system_prompt so spec-mode can
    override the default.
    """
    global client, model, backend

    # Both backends share the retry loop; only the inner call differs.
    if backend == "portkey" and not client:
        raise ValueError("Portkey client not initialised. Call setup() first.")
    if backend == "direct" and not direct_llm:
        raise ValueError(
            "Direct backend not initialised. Call setup_direct() first."
        )

    for attempt in range(max_retries):
        try:
            logger.info(
                f"API call attempt {attempt + 1}/{max_retries} "
                f"(backend={backend})"
            )
            if backend == "direct":
                return _make_api_call_direct(prompt, system_prompt)
            return _make_api_call(prompt, system_prompt)
        except Exception as exc:
            logger.warning(f"API call attempt {attempt + 1} failed: {exc}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay * (2 ** attempt))
            else:
                logger.error(f"All {max_retries} API call attempts failed")
                raise



def _make_api_call(prompt: str, system_prompt: str = SYSTEM_PROMPT) -> str:
    """Send a chat-completion request through the Portkey AI Gateway."""
    global client, model, max_tokens

    completion = client.chat.completions.create(
        model=model,
        max_tokens=max_tokens,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ],
    )

    choice = completion.choices[0]
    response = choice.message.content
    finish_reason = getattr(choice, "finish_reason", None)

    # Diagnose None content (the bug that hit attempt 1, try 1)
    if response is None:
        raise ValueError(
            f"LLM returned None content (finish_reason={finish_reason}). "
            f"This often means a safety filter triggered or the model "
            f"produced no output."
        )

    # Diagnose truncation
    if finish_reason in ("length", "max_tokens", "MAX_TOKENS"):
        logger.warning(
            f"⚠️  Response TRUNCATED at {len(response)} chars "
            f"(finish_reason={finish_reason}). "
            f"Increase --max-tokens or split the prompt."
        )
    elif finish_reason not in ("stop", "end_turn", "STOP", None):
        logger.warning(f"Unexpected finish_reason: {finish_reason}")

    logger.info(
        f"API response received ({len(response)} chars, "
        f"finish_reason={finish_reason})"
    )
    return response

# ─────────────────────────────────────────────────────────────────────────────
# Response Parsing
# ─────────────────────────────────────────────────────────────────────────────

# Section keys in the order they appear in the prompt
SECTION_KEYS = [
    "analysis",
    "sequence_item",
    "sequence",
    "sequencer",
    "driver",
    "monitor",
    "scoreboard",
    "coverage",
    "agent",
    "env",
    "test",
    "tb_top",
    "compile_order",
]

# ─── NEW: Spec-mode adds an INTERFACE section to the response. ───────────────
SECTION_KEYS_SPEC = [
    "analysis",
    "interface",      # only present in spec mode
    "sequence_item",
    "sequence",
    "sequencer",
    "driver",
    "monitor",
    "scoreboard",
    "coverage",
    "agent",
    "env",
    "test",
    "tb_top",
    "compile_order",
]

# Map section key to the header string the LLM is instructed to produce
SECTION_HEADERS = {k: k.upper() + ":" for k in SECTION_KEYS}
SECTION_HEADERS_SPEC = {k: k.upper() + ":" for k in SECTION_KEYS_SPEC}


def _strip_code_fences(text: str) -> str:
    """Remove markdown code fences and optional language tags."""
    text = re.sub(r"```(?:systemverilog|sv|verilog)?\s*\n?", "", text)
    text = text.replace("```", "")
    return text.strip()


def extract_sections(response_text: str, mode: str = "rtl") -> dict:
    """Parse the LLM response into a dict keyed by SECTION_KEYS.

    mode="rtl"  → original behaviour (no INTERFACE section expected)
    mode="spec" → also extracts an INTERFACE section (added for .txt input)
    """
    keys = SECTION_KEYS_SPEC if mode == "spec" else SECTION_KEYS
    headers = SECTION_HEADERS_SPEC if mode == "spec" else SECTION_HEADERS

    results = {}
    resp_lower = response_text.lower()

    for idx, key in enumerate(keys):
        header = headers[key].lower()
        start = resp_lower.find(header)
        if start == -1:
            logger.warning(f"Section '{key}' not found in response")
            results[key] = ""
            continue

        start += len(header)

        # End is the start of the next section or end-of-string
        end = len(resp_lower)
        if idx < len(keys) - 1:
            next_header = headers[keys[idx + 1]].lower()
            next_pos = resp_lower.find(next_header, start)
            if next_pos != -1:
                end = next_pos

        raw = response_text[start:end].strip()

        # Strip code fences for code sections; leave analysis/compile_order as-is
        if key not in ("analysis", "compile_order"):
            raw = _strip_code_fences(raw)

        results[key] = raw

    return results


# ─────────────────────────────────────────────────────────────────────────────
# File-Existence Check 
# ─────────────────────────────────────────────────────────────────────────────
def check_files_exist(
    design_name: str,
    output_dir: str,
    model_name: str,
    version: int,
) -> bool:
    """Return True if the output directory already contains results."""
    base = os.path.splitext(design_name)[0]
    target_dir = os.path.join(output_dir, model_name, base, f"v{version}")
    marker = os.path.join(target_dir, "tb_top.sv")
    return os.path.exists(marker)


# ─────────────────────────────────────────────────────────────────────────────
# File Saving
# ─────────────────────────────────────────────────────────────────────────────

# Which sections map to which output filenames
_FILE_MAP = {
    "sequence_item": "{base}_seq_item.sv",
    "sequence":      "{base}_seq.sv",
    "sequencer":     "{base}_sequencer.sv",
    "driver":        "{base}_driver.sv",
    "monitor":       "{base}_monitor.sv",
    "scoreboard":    "{base}_scoreboard.sv",
    "coverage":      "{base}_coverage.sv",
    "agent":         "{base}_agent.sv",
    "env":           "{base}_env.sv",
    "test":          "{base}_test.sv",
    "tb_top":        "tb_top.sv",
}

# ─── NEW: Spec-mode also writes an interface file ────────────────────────────
_FILE_MAP_SPEC = dict(_FILE_MAP)
_FILE_MAP_SPEC["interface"] = "{base}_if.sv"


def save_testbench(
    design_name: str,
    sections: dict,
    output_dir: str,
    model_name: str,
    version: int,
    mode: str = "rtl",
):
    """Write every extracted UVM component to its own file."""
    base = os.path.splitext(design_name)[0]
    target_dir = os.path.join(output_dir, model_name, base, f"v{version}")
    os.makedirs(target_dir, exist_ok=True)

    file_map = _FILE_MAP_SPEC if mode == "spec" else _FILE_MAP
    section_keys = SECTION_KEYS_SPEC if mode == "spec" else SECTION_KEYS

    header_comment = (
        f"// ─── Auto-generated UVM Testbench ───\n"
        f"// Generated by UVM_TestBench_Gen on "
        f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"// Source design : {design_name}\n"
        f"// Input mode    : {mode}\n"
        f"// LLM model     : {model_name}\n"
        f"// Backend       : {backend}\n"
        f"// Version        : {version}\n"
        f"// ────────────────────────────────────\n\n"
    )

    saved = []
    for key, tmpl in file_map.items():
        code = sections.get(key, "")
        if not code.strip():
            logger.warning(f"Section '{key}' is empty – skipping file write")
            continue

        fname = tmpl.format(base=base)
        fpath = os.path.join(target_dir, fname)
        with open(fpath, "w") as fh:
            fh.write(header_comment + code.strip() + "\n")
        saved.append(fname)

    # Save the analysis as a readme
    analysis = sections.get("analysis", "")
    if analysis.strip():
        with open(os.path.join(target_dir, "ANALYSIS.md"), "w") as fh:
            fh.write(f"# Design Analysis – {design_name}\n\n{analysis}\n")
        saved.append("ANALYSIS.md")

    # Save compile order
    compile_order = sections.get("compile_order", "")
    if compile_order.strip():
        with open(os.path.join(target_dir, "compile_order.txt"), "w") as fh:
            fh.write(compile_order.strip() + "\n")
        saved.append("compile_order.txt")

    # Save a combined single-file version for convenience
    combined_path = os.path.join(target_dir, f"{base}_uvm_tb_all.sv")
    with open(combined_path, "w") as fh:
        fh.write(header_comment)
        for key in section_keys:
            if key in ("analysis", "compile_order"):
                continue
            code = sections.get(key, "")
            if code.strip():
                label = UVM_COMPONENTS.get(key, {}).get(
                    "label", key.upper()
                )
                # Spec-mode interface isn't in UVM_COMPONENTS; label it manually
                if key == "interface":
                    label = "Interface (SystemVerilog) — generated from spec"
                fh.write(f"// {'═'*60}\n")
                fh.write(f"// {label}\n")
                fh.write(f"// {'═'*60}\n\n")
                fh.write(code.strip() + "\n\n")
    saved.append(f"{base}_uvm_tb_all.sv")

    logger.info(f"Saved {len(saved)} files to {target_dir}")
    return target_dir


# ─────────────────────────────────────────────────────────────────────────────
# Single-Task Processor 
# ─────────────────────────────────────────────────────────────────────────────
def process_single_task(
    design_name: str,
    design_code: str,
    output_dir: str,
    version: int,
    mode: str = "rtl",
) -> tuple:
    """Process one design → UVM testbench generation. Returns (status, msg).

    mode="rtl"  → input is .v/.sv, use original prompt + parser
    mode="spec" → input is .txt, use spec prompt + spec parser (incl. interface)
    """
    task_id = f"{design_name}-v{version}"
    logger.info(f"Starting task: {task_id} (mode={mode})")

    try:
        # Skip if already done
        if check_files_exist(design_name, output_dir, model, version):
            logger.info(f"Task {task_id}: already exists – skipping")
            return ("skipped", design_name)

        # Build prompt + select system prompt based on mode
        logger.info(f"Task {task_id}: constructing prompt ({mode})")
        if mode == "spec":
            prompt = construct_prompt_spec(design_code, design_name)
            sys_prompt = SYSTEM_PROMPT_SPEC
        else:
            prompt = construct_prompt(design_code, design_name)
            sys_prompt = SYSTEM_PROMPT

        # Call LLM
        logger.info(f"Task {task_id}: calling LLM")
        response = model_inference(prompt, system_prompt=sys_prompt)

        #DEBUG: save raw LLM response
        with open(f"raw_llm_response_{task_id}.txt", "w") as f:
            f.write(response)

        # Parse response
        logger.info(f"Task {task_id}: parsing response")
        sections = extract_sections(response, mode=mode)

        # Validate: at minimum tb_top and driver should be non-empty
        required_sections = ("tb_top", "driver", "monitor")
        if mode == "spec":
            required_sections = required_sections + ("interface",)
        for required in required_sections:
            if not sections.get(required, "").strip():
                raise ValueError(
                    f"Required section '{required}' is empty in LLM response"
                )

        # Save
        logger.info(f"Task {task_id}: saving files")
        dest = save_testbench(
            design_name, sections, output_dir, model, version, mode=mode
        )

        logger.info(f"Task {task_id}: ✅ completed → {dest}")
        return ("success", design_name)

    except Exception as exc:
        logger.error(f"Task {task_id}: ❌ failed – {exc}")
        return ("failed", f"{design_name}: {exc}")


# ─────────────────────────────────────────────────────────────────────────────
# Main Execution 
# ─────────────────────────────────────────────────────────────────────────────
def main(
    version: int,
    design_file: str = None,
    input_dir: str = "./rtl",
    output_dir: str = "./uvm_output",
    num_threads: int = 4,
):
    """Orchestrate batch UVM testbench generation.

    Accepts both RTL files (.v/.sv) and spec files (.txt).  Mode is
    auto-detected per file based on extension.
    """
    global model

    if not model:
        raise ValueError("Model not set. Please set the global 'model' variable.")

    logger.info(f"Starting UVM TestBench generation job (v{version})")
    logger.info(
        f"Model: {model}, Backend: {backend}, Threads: {num_threads}"
    )

    # Load designs / specs.  Each item is (name, content, mode).
    if design_file:
        loaded, mode = load_inputs(design_file)
        items = [(name, code, mode) for name, code in loaded]
        logger.info(f"Loaded single input: {design_file} (mode={mode})")
    else:
        items = load_inputs_dir(input_dir)
        logger.info(f"Loaded {len(items)} inputs from {input_dir}")

    if not items:
        logger.error("No designs to process – exiting")
        return

    # Build task list — one per (name, content, mode)
    tasks = [
        (name, code, output_dir, version, mode)
        for name, code, mode in items
    ]
    logger.info(f"Created {len(tasks)} tasks")

    # Execute with thread pool
    results = []
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = {
            executor.submit(process_single_task, *t): t for t in tasks
        }
        with tqdm(total=len(tasks), desc="Generating UVM TBs", unit="design") as pbar:
            for future in as_completed(futures):
                status, msg = future.result()
                results.append((status, msg))
                pbar.update(1)

    # Summary
    success = sum(1 for s, _ in results if s == "success")
    skipped = sum(1 for s, _ in results if s == "skipped")
    failed  = sum(1 for s, _ in results if s == "failed")

    summary = f"Summary: {success} succeeded, {skipped} skipped, {failed} failed"
    logger.info(summary)

    print(f"\n{'═'*60}")
    print(summary)
    print(f"{'═'*60}")

    if skipped:
        print("\nSkipped (output already exists):")
        for s, m in results:
            if s == "skipped":
                print(f"  ⊘ {m}")

    if failed:
        print("\nFailed:")
        for s, m in results:
            if s == "failed":
                print(f"  ✗ {m}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI Entry Point
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print(
        """
╔══════════════════════════════════════════════════════════════╗
║              🔬  UVM TestBench Generator  🔬                ║
║                                                              ║
║  Automatically generates full UVM testbenches from RTL       ║
║  designs OR text specifications using LLM-powered analysis.  ║
║  Supports Portkey AI Gateway (NYU) or direct provider APIs.  ║
╚══════════════════════════════════════════════════════════════╝
"""
    )

    parser = argparse.ArgumentParser(
        description="UVM TestBench Generator – LLM-powered UVM TB creation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples
────────
  # ─── Portkey backend (NYU users) ──────────────────────────────────────
  # Single RTL design with GPT-4o via Portkey
  python UVM_TestBench_Gen.py --model @gpt-4o/gpt-4o --design alu.v

  # Spec file (.txt) instead of RTL
  python UVM_TestBench_Gen.py --model @gpt-4o/gpt-4o --design alu_spec.txt

  # Use Anthropic Claude via Vertex AI
  python UVM_TestBench_Gen.py \\
      --model @vertexai/anthropic.claude-sonnet-4-6 --design fifo.sv

  # Batch-process a directory (mixes .v/.sv/.txt automatically)
  python UVM_TestBench_Gen.py --model @gpt-4o/gpt-4o \\
      --input-dir ./inputs --threads 4

  # ─── Direct backend (non-NYU users, BYO API key) ──────────────────────
  # In direct mode you can use --model OR --model-choice (they alias).
  #
  # OpenAI — auto-detects ChatGPT wrapper from "gpt-" prefix
  python UVM_TestBench_Gen.py --backend direct --model gpt-4o \\
      --design alu.v

  # Anthropic — auto-detects Claude wrapper from "claude-" prefix
  python UVM_TestBench_Gen.py --backend direct --model claude-sonnet-4-5 \\
      --design alu_spec.txt

  # Google Gemini — auto-detects Gemini wrapper from "gemini-" prefix
  python UVM_TestBench_Gen.py --backend direct --model gemini-2.5-flash \\
      --design fifo.sv

  # Explicit provider override 
  python UVM_TestBench_Gen.py --backend direct \\
      --provider ChatGPT --model-choice gpt-4o --design alu.v

Environment
───────────
  Portkey backend (default):
    export PORTKEY_API_KEY="your-portkey-api-key"

  Direct backend (--backend direct):
    export OPENAI_API_KEY="sk-..."          # for ChatGPT (gpt-* / o-series)
    export CLAUDE_API_KEY="sk-ant-..."      # for Claude  (claude-* models)
    export GEMINI_API_KEY="..."             # for Gemini  (gemini-* models)
    export MODEL="ChatGPT"                  # 

  You only need the env var for the provider you actually use.

Switching backends
──────────────────
  • Default is --backend portkey  → unchanged original behaviour.
  • Pass --backend direct to use your own OpenAI/Anthropic/Google key.
  • In direct mode, use BARE model names (e.g. 'gpt-4o', 'claude-sonnet-4-5',
    'gemini-2.5-flash') — NOT Portkey-style '@provider/model' strings.
  • Provider auto-detection: gpt-/o- → ChatGPT, claude- → Claude,
    gemini- → Gemini.  Override with --provider or os.environ['MODEL'].
""",
    )

    parser.add_argument(
        "--model",
        type=str,
        required=True,
        help=(
            "Model name. With --backend portkey use Portkey strings "
            "(e.g. @gpt-4o/gpt-4o, @vertexai/gemini-2.5-pro). "
            "With --backend direct use bare names (e.g. gpt-4o, "
            "claude-sonnet-4-5, gemini-2.5-pro)."
        ),
    )
    # ─── NEW: backend selector ───────────────────────────────────────────
    parser.add_argument(
        "--backend",
        type=str,
        choices=["portkey", "direct"],
        default="portkey",
        help=(
            "Which API backend to use. 'portkey' (default) routes through "
            "the NYU Portkey AI Gateway (requires PORTKEY_API_KEY). "
            "'direct' calls the OpenAI / Anthropic / Google APIs directly "
            "using your own API key from the provider's website."
        ),
    )
    parser.add_argument(
        "--provider",
        type=str,
        choices=["ChatGPT", "Claude", "Gemini"],
        default=None,
        help=(
            "[direct backend only] Which E wrapper class to use. "
            "Same strings accepts for os.environ['MODEL']. "
            "If omitted, falls back to the MODEL env var, then to "
            "auto-detection from --model-choice."
        ),
    )
    parser.add_argument(
        "--model-choice",
        type=str,
        default=None,
        help=(
            "[direct backend only] The specific model VERSION, e.g. 'gpt-4o', "
            "'claude-sonnet-4-5', 'gemini-2.5-flash'. If omitted, uses "
            "the module-level model_choice global at the top of this file."
        ),
    )
    parser.add_argument(
        "--design",
        type=str,
        default=None,
        help=(
            "Single input file: .v/.sv (RTL) OR .txt (specification). "
            "Mode is auto-detected from the extension."
        ),
    )
    parser.add_argument(
        "--input-dir",
        type=str,
        default="./rtl",
        help=(
            "Directory containing input files. Both RTL (.v/.sv) and spec "
            "(.txt) files are picked up automatically. (default: ./rtl)"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="./uvm_output",
        help="Output directory (default: ./uvm_output)",
    )
    parser.add_argument(
        "--attempts",
        type=int,
        default=1,
        help="Number of generation attempts per design (default: 1)",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=4,
        help="Parallel threads for batch processing (default: 4)",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=16384,
        help="Max output tokens for the LLM response (default: 16384)",
    )

    args = parser.parse_args()

    # Timestamped log file
    log_file = f"uvm_gen_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[logging.FileHandler(log_file), logging.StreamHandler()],
        force=True,
    )
    logger.info("UVM TestBench Generator started")
    logger.info(f"Arguments: {vars(args)}")

    try:
        # ─── NEW: route to the right setup function based on --backend ──
        backend = args.backend
        model = args.model
        max_tokens = args.max_tokens

        if backend == "portkey":
            setup()
            logger.info(f"Using Portkey AI Gateway / {model}")
        else:  # direct
            # Override the module-level model_choice if --model-choice given,
            # otherwise fall back to --model (for users who only pass --model
            # in direct mode), otherwise keep the default at the top of file.
            if args.model_choice:
                model_choice = args.model_choice
            elif args.model:
                model_choice = args.model
            # else: use the existing module-global model_choice as-is
            logger.info(f"Direct backend: model_choice={model_choice}")

            setup_direct(cli_provider=args.provider)
            logger.info(
                f"Using DIRECT backend ({direct_provider}) / {model_choice}"
            )

        for attempt in range(1, args.attempts + 1):
            print(f"\n{'#'*60}")
            print(f"# Attempt {attempt}/{args.attempts}  "
                  f"({args.threads} threads, backend={backend})")
            print(f"{'#'*60}\n")

            main(
                version=attempt,
                design_file=args.design,
                input_dir=args.input_dir,
                output_dir=args.output_dir,
                num_threads=args.threads,
            )

        print(f"\n{'═'*60}")
        print("All tasks completed!")
        print(f"Log: {log_file}")
        print(f"{'═'*60}")

    except Exception as exc:
        logger.error(f"Fatal error: {exc}")
        print(f"\n❌ Error: {exc}")
        sys.exit(1)
