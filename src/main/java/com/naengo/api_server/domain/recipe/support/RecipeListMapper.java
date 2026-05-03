package com.naengo.api_server.domain.recipe.support;

import com.naengo.api_server.domain.recipe.dto.RecipeListItemResponse;
import com.naengo.api_server.domain.recipe.dto.RecipeListResponse;
import com.naengo.api_server.domain.recipe.entity.Recipe;
import com.naengo.api_server.domain.recipe.entity.RecipeStats;
import com.naengo.api_server.domain.user.repository.UserRepository;
import com.naengo.api_server.domain.user.support.AuthorDisplayName;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

/**
 * Page&lt;Recipe&gt; → RecipeListResponse 매핑.
 * RecipeService.listApproved 와 ScrapService.listMine 가 공유.
 * 작성자 닉네임은 일괄 조회로 N+1 방지.
 */
@Component
@RequiredArgsConstructor
public class RecipeListMapper {

    private final UserRepository userRepository;

    public RecipeListResponse toResponse(Page<Recipe> page) {
        List<Recipe> content = page.getContent();

        List<Long> authorIds = content.stream()
                .map(Recipe::getAuthorId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();

        Map<Long, String> nicknameMap = new HashMap<>();
        if (!authorIds.isEmpty()) {
            userRepository.findAllById(authorIds)
                    .forEach(u -> nicknameMap.put(u.getUserId(), u.getNickname()));
        }

        List<RecipeListItemResponse> items = content.stream().map(r -> {
            RecipeStats s = r.getStats();
            int likes = s == null ? 0 : s.getLikesCount();
            int scraps = s == null ? 0 : s.getScrapCount();
            String raw = r.getAuthorId() == null ? null : nicknameMap.get(r.getAuthorId());
            return new RecipeListItemResponse(
                    r.getRecipeId(),
                    r.getTitle(),
                    r.getDescription(),
                    r.getImageUrl(),
                    AuthorDisplayName.of(raw),
                    r.getAuthorType(),
                    r.getDifficulty(),
                    r.getCookingTime(),
                    likes,
                    scraps,
                    r.getCreatedAt()
            );
        }).collect(Collectors.toList());

        return new RecipeListResponse(
                items,
                page.getNumber(),
                page.getSize(),
                page.getTotalElements(),
                page.getTotalPages()
        );
    }
}
