#!/bin/zsh

# ANTHROPIC_API_KEY 환경변수 확인
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "에러: ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다" >&2
  exit 1
fi

# 인자 파싱
for arg in "$@"; do
  case $arg in
    --compare=*)
      compare_branch="${arg#*=}"
      ;;
  esac
done

# compare_branch가 지정되지 않은 경우 기본값 'develop' 사용
compare_branch=${compare_branch:-develop}

# 지정된 브랜치와 비교하여 diff 생성
git fetch origin ${compare_branch}:${compare_branch} 2>/dev/null || true
git diff ${compare_branch} > pr.diff

# diff 내용 읽기
diff_content=$(cat pr.diff)

# 비교 브랜치 이후의 커밋들만 가져오기
commit_history=$(git log ${compare_branch}..HEAD --pretty=format:"%h %s (%an, %ar)" --reverse)

# 프롬프트 준비
prompt="당신은 명료한 PR 메시지를 작성하는 전문 개발자입니다.
git diff와 커밋 이력을 분석하여 PR 메시지를 생성해주세요.

1. PR 메시지는 마크다운 포맷으로 작성해주세요.
2. PR 메시지에 흐름도를 포함하세요. 하나의 흐름도로 표현할 수 없다면, 분리해서 여러 벌 그려주세요.

커밋 이력:
$commit_history

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

# API 응답에서 리뷰 내용만 추출
review_content=$(echo "$response" | sed 's/.*"text":"//' | sed 's/"}],"stop_reason".*//')

# 에러 발생 시에만 디버그 정보 출력
if [[ -z "$review_content" || "$review_content" == "null" ]]; then
  echo "에러: PR 리뷰 생성 실패" >&2
  echo "API 응답:" >&2
  echo "$response" | tr -d '\000-\037' | jq '.' >&2
  exit 1
fi

# 성공 시 리뷰 내용을 출력하고 클립보드에 복사
if command -v pbcopy >/dev/null 2>&1; then
    # macOS
    echo "$review_content" | pbcopy
    echo "$review_content"
    echo "\n리뷰 내용이 클립보드에 복사되었습니다."
else
    echo "경고: pbcopy이 설치되어 있지 않아 클립보드 복사가 불가능합니다."
    echo "$review_content"
fi

# 임시 파일 삭제
rm -f pr.diff
