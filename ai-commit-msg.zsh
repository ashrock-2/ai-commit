#!/bin/zsh

# ANTHROPIC_API_KEY 환경변수 확인
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "에러: ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다" >&2
  exit 1
fi

# Git diff 컨텍스트 가져오기
diff_context=$(git diff --cached --diff-algorithm=minimal)

if [[ -z "$diff_context" ]]; then
  echo "에러: 스테이징된 변경사항이 없습니다" >&2
  exit 1
fi

# 최근 3개의 커밋 메시지 가져오기
recent_commits=$(git log -3 --pretty=format:"%B" | sed 's/"/\\"/g')

# 프롬프트 준비
prompt="다음 구조를 따르는 git 커밋 메시지를 생성해주세요:
1. 첫 줄: conventional commit 형식 (type: 간단한 설명) 
   (feat, fix, docs, style, refactor, perf, test, chore 등의 시맨틱 타입 사용)
2. 필요한 경우 추가 설명을 불릿 포인트로 작성:
   - 두 번째 줄은 비워두기
   - 짧고 직접적으로 작성
   - 변경된 내용에 집중
   - 간결하게 유지
   - 과도한 설명 피하기
   - 불필요한 형식적인 언어 사용 피하기

커밋 메시지만 반환하세요 - 소개, 설명, 따옴표 없이.
한국어로 작성하세요. 단, 파일 이름, 함수 이름은 원문 그대로 사용해도 좋습니다.

최근 커밋 메시지 (스타일 참고용):
$recent_commits

변경사항:
$diff_context"

# JSON용 프롬프트 이스케이프
json_escaped_prompt=$(jq -n --arg prompt "$prompt" '$prompt')

# Claude API 호출
response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --data-raw "{
        \"model\": \"claude-3-7-sonnet-20250219\",
        \"max_tokens\": 1024,
        \"messages\": [
            {
                \"role\": \"user\",
                \"content\": ${json_escaped_prompt}
            }
        ]
    }")

# API 응답에서 커밋 메시지만 추출하고 줄바꿈 처리
commit_message=$(echo "$response" | tr -d '\000-\037' | jq -r '.content[0].text' | sed 's/- /\n- /g')

# 에러 발생 시에만 디버그 정보 출력
if [[ -z "$commit_message" || "$commit_message" == "null" ]]; then
  echo "에러: 커밋 메시지 생성 실패" >&2
  echo "API 응답:" >&2
  echo "$response" | tr -d '\000-\037' | jq '.' >&2
  exit 1
fi

# 성공 시 커밋 메시지만 출력
echo "$commit_message"
