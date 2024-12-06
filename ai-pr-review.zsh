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
    *)
      # 다른 옵션들을 위한 공간
      ;;
  esac
done

# compare_branch가 지정되지 않은 경우 기본값 'develop' 사용
compare_branch=${compare_branch:-develop}

# 현재 브랜치 이름 가져오기
current_branch=$(git branch --show-current)

# 현재 브랜치의 PR 번호 가져오기
pr_info=$(gh pr list --head "$current_branch" --json number,title,body,additions,deletions,changedFiles --limit 1)
if [[ -z "$pr_info" ]]; then
  echo "에러: 현재 브랜치($current_branch)의 PR을 찾을 수 없습니다" >&2
  exit 1
fi

# PR 정보 추출
pr_number=$(echo "$pr_info" | jq -r '.[0].number')
title=$(echo "$pr_info" | jq -r '.[0].title')
body=$(echo "$pr_info" | jq -r '.[0].body')
changed_files=$(echo "$pr_info" | jq -r '.[0].changedFiles')
additions=$(echo "$pr_info" | jq -r '.[0].additions')
deletions=$(echo "$pr_info" | jq -r '.[0].deletions')

# PR의 diff 가져오기
gh pr diff "$pr_number" > pr.diff

# diff 내용 읽기
diff_content=$(cat pr.diff)

# 프롬프트 준비
prompt="당신은 꼼꼼하고 건설적인 PR 리뷰를 작성하는 시니어 개발자입니다.
아래 PR의 내용을 분석하여 상세한 리뷰를 작성해주세요.

PR 정보:
제목: $title
설명: $body
변경된 파일 수: $changed_files
추가된 라인: $additions
삭제된 라인: $deletions

변경사항:
\`\`\`diff
$diff_content
\`\`\`

리뷰 작성 가이드라인:
1. 코드 품질 관점:
   - 코드 구조와 설계
   - 성능 고려사항
   - 잠재적인 버그나 엣지 케이스
   - 테스트 커버리지

2. 리뷰 형식:
   - 긍정적인 피드백 포함
   - 구체적이고 실행 가능한 제안 제시
   - 중요도에 따라 'Major'/'Minor' 표시
   - 코드의 특정 부분 참조 시 파일명과 라인 번호 포함

3. 언어:
   - 기술 용어는 영문으로 유지
   - 설명과 피드백은 한국어로 작성
   - 공손하고 건설적인 톤 유지

리뷰 내용만 반환하세요 - 소개나 추가 설명 없이."

# JSON용 프롬프트 이스케이프
json_escaped_prompt=$(jq -n --arg prompt "$prompt" '$prompt')

# Claude API 호출
response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --data-raw "{
        \"model\": \"claude-3-5-sonnet-20241022\",
        \"max_tokens\": 4096,
        \"messages\": [
            {
                \"role\": \"user\",
                \"content\": ${json_escaped_prompt}
            }
        ]
    }")

# API 응답에서 리뷰 내용만 추출
review_content=$(echo "$response" | tr -d '\000-\037' | jq -r '.content[0].text')

# 에러 발생 시에만 디버그 정보 출력
if [[ -z "$review_content" || "$review_content" == "null" ]]; then
  echo "에러: PR 리뷰 생성 실패" >&2
  echo "API 응답:" >&2
  echo "$response" | tr -d '\000-\037' | jq '.' >&2
  exit 1
fi

# 성공 시 리뷰 내용만 출력
echo "$review_content"

# 임시 파일 삭제
rm -f pr.diff 