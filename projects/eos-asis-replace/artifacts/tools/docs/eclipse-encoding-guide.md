# 이클립스 인코딩 설정 가이드

> MAR/EOS 이관 프로젝트 — 한글 파일명 인코딩 이슈 대응
> 대상: Eclipse Dynamic Web Project / Java 1.8 / Ant 빌드 / LENA WAS

---

## 1. 핵심 원칙

이클립스 인코딩 설정을 건드리기 전에 반드시 알아야 할 두 가지.

**원칙 1 — 우선순위를 이해하고 손댄다.**
Content Types는 워크스페이스 전역 설정이다. 여기에 값을 박으면 프로젝트별 설정이 무시된다.

**원칙 2 — 이클립스 설정은 `.class` 결과를 결정하지 않는다.**
에디터가 파일을 어떻게 "보여줄지"만 결정한다. 실제 컴파일 결과는 `build.xml`의 `<javac encoding>`이 결정한다.

---

## 2. 인코딩 결정 우선순위

높은 것이 낮은 것을 덮어쓴다.

| 순위 | 계층 | 설정 위치 |
|:---:|---|---|
| 1 | 파일 개별 지정 | 파일 우클릭 → Properties → Resource |
| 2 | 파일 내용 감지 | XML 선언, JSP `pageEncoding`, BOM |
| 3 | **Content Types 기본값** | Preferences → General → Content Types |
| 4 | 프로젝트 설정 | 프로젝트 우클릭 → Properties → Resource |
| 5 | 워크스페이스 기본값 | Preferences → General → Workspace |

3번에 값을 넣는 순간 4·5번은 무시된다.
따라서 **Content Types는 가능한 한 비워두고, 프로젝트/워크스페이스 레벨에서 관리**한다.

---

## 3. Content Types 항목별 권장 설정

`Preferences → General → Content Types` 화면 기준.

| Content Type | 권장값 | 근거 |
|---|---|---|
| **Text** (루트) | 비움 | 값을 넣으면 하위 전체를 강제 상속. **절대 건드리지 말 것** |
| **Java Source File** | 비움 | 프로젝트마다 MS949/UTF-8이 다를 수 있으므로 프로젝트 레벨에 위임 |
| **Java Properties File** | `ISO-8859-1` 유지 | Java 8 `Properties.load()` 스펙 자체가 Latin-1. 변경 시 런타임과 불일치 |
| **Properties File** | 비움 | Java Properties File의 상위 격, 중복 지정 불필요 |
| **JSP** | 비움 또는 `UTF-8` | 파일 내 `pageEncoding` 선언이 우선. 선언 없는 파일 대비용으로만 지정 |
| **XML** | 비움 | XML 선언(`<?xml encoding="..."?>`)이 항상 우선 |
| **HTML / CSS** | 비움 | meta 태그 / `@charset` 우선 |

### 변경 방법
1. 좌측 트리에서 Content Type 선택
2. 하단 `Default encoding` 입력란에 값 입력 (또는 비우기)
3. **`Update` 버튼 클릭** ← 이 단계를 빼먹으면 반영되지 않음
4. `Apply and Close`

---

## 4. 실제로 설정해야 할 곳

### 4-1. 워크스페이스 기본값

```
Preferences → General → Workspace → Text file encoding
```

권장: **UTF-8**
신규 프로젝트 및 명시적 설정이 없는 프로젝트의 기본값이 된다.

### 4-2. 프로젝트별 설정 (중요)

```
프로젝트 우클릭 → Properties → Resource → Text file encoding
```

| 상황 | 설정값 |
|---|---|
| 소스가 아직 MS949로 저장된 레거시 프로젝트 | `MS949` |
| `Convert-ToUtf8.ps1` 변환 완료 후 | `UTF-8` |
| 신규 프로젝트 (`lena-encoding-test` 등) | `UTF-8` |

---

## 5. ⚠️ 가장 위험한 함정 — 순서를 지킬 것

### 잘못된 순서 (파일이 실제로 파괴됨)

```
1. 프로젝트 인코딩을 UTF-8로 변경
   → 에디터에서 MS949 한글이 �로 표시됨
2. 그 상태에서 파일 편집 후 저장
   → �가 그대로 UTF-8로 저장됨 (복구 불가)
```

ISO-8859-1이나 UTF-8로 잘못 읽힌 한글은 U+FFFD(`�`)로 치환되며, **이 시점에 원본 바이트 정보가 소실된다.** 저장하는 순간 되돌릴 수 없다.

### 올바른 순서

```
1. 프로젝트 인코딩을 MS949로 설정   ← 한글이 정상 표시되는지 눈으로 확인
2. Scan-JavaSources.ps1 로 대상 파일 식별
3. Convert-ToUtf8.ps1 -WhatIf 로 드라이런
4. Convert-ToUtf8.ps1 실행 (BOM 없는 UTF-8로 변환)
5. 프로젝트 인코딩을 UTF-8로 변경
6. 이클립스에서 F5 (Refresh) 후 한글 정상 표시 확인
7. build.xml 의 javac encoding 을 UTF-8 로 변경
8. Clean Build
9. javap -v 로 상수 풀 검증
```

**변환 전에는 절대 프로젝트 인코딩을 바꾸지 않는다.**

---

## 6. Properties 파일 한글 처리

### 옵션 A — ISO-8859-1 유지 (권장, 레거시 호환)

한글은 유니코드 이스케이프로 저장한다.

```properties
error.filename=\uD30C\uC77C\uBA85 \uC624\uB958
```

Ant `native2ascii` 태스크로 자동 변환 가능.

### 옵션 B — UTF-8로 전환

이클립스 설정만 바꾸면 안 되고, **Spring 설정도 함께 맞춰야 한다.**

```xml
<bean id="messageSource"
      class="org.springframework.context.support.ReloadableResourceBundleMessageSource">
    <property name="basename" value="classpath:messages"/>
    <property name="defaultEncoding" value="UTF-8"/>
</bean>

<bean class="org.springframework.beans.factory.config.PropertyPlaceholderConfigurer">
    <property name="location" value="classpath:config.properties"/>
    <property name="fileEncoding" value="UTF-8"/>
</bean>
```

둘 중 하나만 바꾸면 다시 깨진다.

---

## 7. 이클립스 설정 ≠ 컴파일 결과

이 문서에서 가장 중요한 부분.

```
┌─────────────────────────────────────────────┐
│  이클립스 Content Types / Project Encoding  │  ← 에디터 표시용
│  = 파일을 어떻게 "읽고 보여줄지"            │
└─────────────────────────────────────────────┘
                    ✗ 무관
┌─────────────────────────────────────────────┐
│  build.xml  <javac encoding="UTF-8">        │  ← 실제 .class 생성
│  = 상수 풀에 어떤 바이트가 박힐지           │
└─────────────────────────────────────────────┘
```

이클립스에서 한글이 멀쩡히 보여도 Ant `javac`의 encoding이 다르면 `.class` 상수 풀에는 U+FFFD 또는 Latin-1 모지바케가 박힌다.

### 세 가지가 반드시 일치해야 한다

```
파일의 실제 바이트 인코딩
    == 이클립스 프로젝트 인코딩
    == javac -encoding
```

### build.xml 설정

```xml
<property name="build.encoding" value="UTF-8"/>

<javac srcdir="${src.dir}"
       destdir="${classes.dir}"
       encoding="${build.encoding}"
       source="1.8" target="1.8"
       includeantruntime="false">
    <classpath refid="project.classpath"/>
</javac>
```

### Ant JRE 설정 확인

```
Run → External Tools Configurations → build.xml → JRE 탭
→ Separate JRE: JDK 1.8 선택
```

이클립스 내장 JDK(21 등)로 실행하면 `invalid source release: 1.7` 오류가 발생한다.

---

## 8. 검증 체크리스트

설정을 바꾼 뒤 반드시 확인한다.

- [ ] 이클립스 에디터에서 한글 리터럴이 정상 표시되는가
- [ ] `Clean Build` 후 `javap -v Constants.class` 상수 풀에 정상 한글이 보이는가
- [ ] `Constants`를 참조하는 **모든 클래스**(`LogController` 등)를 함께 재컴파일했는가
- [ ] `WEB-INF/lib`에 중복 jar가 없는가
- [ ] WAS work/cache 디렉터리를 삭제했는가
- [ ] 서버를 재기동했는가

> **`static final String` 인라이닝 주의**
> 상수 정의 클래스만 재컴파일하면 런타임에 아무 효과가 없다.
> 컴파일 시점에 참조 클래스의 상수 풀로 값이 **복사**되기 때문이다.
> 반드시 참조 클래스까지 함께 재컴파일·재배포해야 한다.

---

## 9. 요약

| 하지 말 것 | 할 것 |
|---|---|
| Content Types의 `Text` 루트에 인코딩 지정 | 비워두기 |
| Content Types에서 Java Source 인코딩 강제 | 프로젝트 레벨에서 지정 |
| Java Properties File을 UTF-8로 변경 | ISO-8859-1 유지 (또는 Spring 동시 수정) |
| 변환 전 프로젝트 인코딩 변경 | 변환 → 확인 → 인코딩 변경 순서 |
| 이클립스 설정만 믿기 | `javap -v`로 최종 검증 |
