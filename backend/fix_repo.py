import sys

with open('app/repository.py', 'r', encoding='utf-8') as f:
    content = f.read()

# The problematic method is currently at the end of the file, starting at:
#     async def get_knowledge_graph(
method_start = "    async def get_knowledge_graph("

idx = content.find(method_start)
if idx != -1:
    method_code = content[idx:]
    content = content[:idx]
    
    # Now find where the class ends, which is right before project_repository = SupabaseProjectRepository()
    class_end = "project_repository = SupabaseProjectRepository()"
    insert_idx = content.find(class_end)
    if insert_idx != -1:
        new_content = content[:insert_idx] + method_code + "\n" + content[insert_idx:]
        with open('app/repository.py', 'w', encoding='utf-8') as f:
            f.write(new_content)
        print("Fixed indentation and placement of get_knowledge_graph")
    else:
        print("Could not find class end")
else:
    print("Could not find method start")
