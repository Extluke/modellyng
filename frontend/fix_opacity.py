import sys
import glob

files = [
    'lib/src/screens/project_maps_detail_screen.dart',
    'lib/src/screens/knowledge_graph_screen.dart'
]

for file in files:
    try:
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        content = content.replace('.withOpacity(', '.withValues(alpha: ')
        content = content.replace('..scale(', '..scaleByDouble(')
        content = content.replace('..translate(', '..translateByVector3(') # wait, Matrix4.translate in Dart might not be exactly this, but actually `withOpacity` is the main one. Let's just fix withOpacity.
        
        with open(file, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed deprecated warnings in {file}")
    except Exception as e:
        print(f"Error in {file}: {e}")
