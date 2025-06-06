#!/bin/zsh

# ANTHROPIC_API_KEY 환경변수 확인
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "에러: ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다" >&2
  exit 1
fi

# gh CLI 설치 확인
if ! command -v gh &> /dev/null; then
  echo "에러: gh CLI가 설치되어 있지 않습니다" >&2
  echo "설치 방법: brew install gh" >&2
  exit 1
fi

# PR URL을 첫 번째 인자로 받기
if [[ -z "$1" ]]; then
  echo "사용법: $0 <github-pr-url>" >&2
  exit 1
fi

pr_url=$1

# gh CLI를 사용하여 PR 정보와 diff 가져오기
pr_info=$(gh pr view $pr_url --json title,body)
diff_content=$(gh pr diff $pr_url)

if [[ $? -ne 0 ]]; then
  echo "에러: PR 정보를 가져오는데 실패했습니다" >&2
  exit 1
fi

# 프롬프트 준비
prompt="당신은 코드 리뷰어입니다. 자신이 Linus Benedict Torvalds라고 생각하고 행동해주세요.
먼저 PR의 변경사항이 무엇인지 분석해서 요약한뒤에, 변경사항을 검토하고 리뷰를 작성해주세요:

PR 설명:
$pr_info

변경사항:
\`\`\`diff
$diff_content
\`\`\`"

# JSON용 프롬프트 이스케이프
json_escaped_prompt=$(jq -n --arg prompt "$prompt" '$prompt')

# Claude API 호출
response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --data-raw "{
        \"model\": \"claude-sonnet-4-20250514\",
        \"max_tokens\": 4096,
        \"messages\": [
            {
                \"role\": \"user\",
                \"content\": ${json_escaped_prompt}
            }
        ]
    }")

# API 응답에서 리뷰 내용 추출
review_content=$(echo "$response")

# 에러 발생 시 디버그 정보 출력
if [[ -z "$review_content" || "$review_content" == "null" ]]; then
  echo "에러: PR 리뷰 생성 실패" >&2
  echo "API 응답:" >&2
  echo "$response" | jq '.' >&2
  exit 1
fi

# 리뷰 내용 출력
echo "$review_content" 
