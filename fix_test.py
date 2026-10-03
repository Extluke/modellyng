import re
import sys

def main():
    try:
        with open('frontend/test/widget_test.dart', 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        for i, line in enumerate(lines):
            # ComparativeMatrixScreen and MapsScreen require onGoToProjects
            if 'ComparativeMatrixScreen(' in line or 'MapsScreen(' in line:
                if 'onGoToProjects' not in lines[i+1]:
                    lines[i] = line.rstrip() + '\n          onGoToProjects: () {},\n'

            # ConceptEvidenceMapScreen and ResearchGapMapScreen require projectId
            if 'ConceptEvidenceMapScreen(' in line or 'ResearchGapMapScreen(' in line:
                if 'projectId' not in lines[i+1]:
                    lines[i] = line.rstrip() + '\n          projectId: \'project-123\',\n'

            # Some lines might have the old onNewProject which should be removed or isn't there anymore.
            # But the flutter analyze error says: The named parameter 'onGoToProjects' isn't defined... at 582:13
            # Wait, line 582 is where I incorrectly added it before! Let me just revert first and then apply a safe regex

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
