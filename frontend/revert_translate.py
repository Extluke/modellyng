import sys

files = [
    'lib/src/screens/project_maps_detail_screen.dart',
    'lib/src/screens/knowledge_graph_screen.dart'
]

for file in files:
    try:
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        content = content.replace('..translateByVector3(', '..translate(')
        content = content.replace('..scaleByDouble(', '..scale(')
        
        with open(file, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Reverted translate and scale in {file}")
    except Exception as e:
        print(f"Error in {file}: {e}")
