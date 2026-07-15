import os
import re

def refactor_module(module_path):
    main_tf_path = os.path.join(module_path, "main.tf")
    if not os.path.exists(main_tf_path):
        return

    with open(main_tf_path, 'r') as f:
        content = f.read()

    # Regex to find variable blocks
    variable_pattern = re.compile(r'((?:#[^\n]*\n)*)variable\s+"[^"]+"\s+\{(?:[^{}]*|\{[^{}]*\})*\}|((?:#[^\n]*\n)*)variable\s+"[^"]+"\s+\{\}')
    
    # Regex to find output blocks
    output_pattern = re.compile(r'((?:#[^\n]*\n)*)output\s+"[^"]+"\s+\{(?:[^{}]*|\{[^{}]*\})*\}')

    variables = []
    outputs = []
    main_content = content

    for match in variable_pattern.finditer(content):
        variables.append(match.group(0))
        main_content = main_content.replace(match.group(0), "")

    for match in output_pattern.finditer(content):
        outputs.append(match.group(0))
        main_content = main_content.replace(match.group(0), "")

    # Clean up empty lines
    main_content = re.sub(r'\n{3,}', '\n\n', main_content).strip() + '\n'

    var_content = "# ==========================================\n# Variables\n# ==========================================\n\n" + "\n\n".join(variables) + '\n'
    out_content = "# ==========================================\n# Outputs\n# ==========================================\n\n" + "\n\n".join(outputs) + '\n'

    with open(main_tf_path, 'w') as f:
        f.write(main_content)
    
    if variables:
        with open(os.path.join(module_path, "variables.tf"), 'w') as f:
            f.write(var_content)

    if outputs:
        with open(os.path.join(module_path, "outputs.tf"), 'w') as f:
            f.write(out_content)


modules_dir = "/home/diljith/Downloads/AWS Production Grade Project/infra/modules"
for mod in os.listdir(modules_dir):
    mod_path = os.path.join(modules_dir, mod)
    if os.path.isdir(mod_path):
        refactor_module(mod_path)
