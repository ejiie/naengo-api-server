package com.naengo.api_server.domain.recipe.repository;

import com.naengo.api_server.domain.recipe.entity.PendingRecipe;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PendingRecipeRepository extends JpaRepository<PendingRecipe, Long> {

    @Query("""
           SELECT p FROM PendingRecipe p
           WHERE p.userId = :userId AND p.isActive = true
           ORDER BY p.createdAt DESC
           """)
    Page<PendingRecipe> findActiveByUserOrderByLatest(@Param("userId") Long userId, Pageable pageable);
}
